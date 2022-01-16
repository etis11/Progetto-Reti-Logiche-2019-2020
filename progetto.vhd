library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity project_reti_logiche is
  port
  (
    i_clk     : in  std_logic; 						--Segnale di CLOCK in ingresso dal TestBench
    i_start   : in  std_logic;						--Segnale di START generato dal TestBench
    i_rst     : in  std_logic;						--Segnale di RESET che inizializza la macchina pronta per ricevere il primo segnale di START
    i_data    : in  std_logic_vector(7 downto 0);	--Segnale(vettore) che arriva dalla memoria in seguito ad una richiesta di lettura
    o_address : out std_logic_vector(15 downto 0);	--Segnale(vettore) di uscita che manda l'indirizzo alla memoria
    o_done    : out std_logic;						--Segnale di uscita che comunica la fine dell'elaborazione e il dato di uscita scritto in memoria
    o_en      : out std_logic;						--Segnale di ENABLE da dover mandare alla memoria per poter comunicare(sia in lettura che scrittura)
    o_we      : out std_logic;						--Segnale WRITE ENABLE da dover mandare alla memoria(=1) per poter scriverci.Per leggere dev'essere 0.
    o_data    : out std_logic_vector (7 downto 0)	--Segnale(vettore) di uscita dal componente verso la memoria
  );
end project_reti_logiche;

architecture FSM of project_reti_logiche is

  type state_type is (s0, s1, s2, s3); --Dichiaro i stati della Macchina a stati finiti.
  signal next_state, current_state : state_type;
  signal input_addr                : std_logic_vector(6 downto 0)  := (others => '0'); --ADDR che dobbiamo codificare
  signal wz_match                  : std_logic                     := '0';             --Abbiamo ricavato il WZ_Base e WZ_OFFSET che ci interessavano!
  signal wz_base                   : std_logic_vector(2 downto 0)  := (others => '0'); --L'indirizzo di WZ_Base posto a 3 bit (8 in totale)
  signal wz_offset                 : std_logic_vector(3 downto 0)  := (others => '0'); --L'offset di dimensione 4 bit che ci interessa per concatenarlo poi
  signal address                   : std_logic_vector(15 downto 0) := (others => '0'); --L'indirizzo attuale mandato alla RAM
  signal previous_address          : std_logic_vector(15 downto 0) := (others => '0'); --L'indirizzo che abbiamo appena letto
  signal done                      : std_logic                     := '0';             --Quando la codifica viene fatta!
  signal enable                    : std_logic                     := '0';             --RAM enable
  signal write                     : std_logic                     := '0';             --RAM write enable
  signal dout                      : std_logic_vector(7 downto 0)  := (others => '0');

begin

  --Gli output delle porte 
  o_address <= address;
  o_done    <= done;
  o_en      <= enable;
  o_we      <= write;
  o_data    <= dout;

  --Qua andiamo a computare tutti gli offset possibili codificati poi come one-hot e cerchiamo di ottenere i 4 bit wz_offset che ci servono!
  wz_offset(0) <= '1' when (unsigned(i_data)+0 = unsigned(input_addr)) else '0'; --WZE Offset 0
  wz_offset(1) <= '1' when (unsigned(i_data)+1 = unsigned(input_addr)) else '0'; --WZE Offset 1
  wz_offset(2) <= '1' when (unsigned(i_data)+2 = unsigned(input_addr)) else '0'; --WZE Offset 2
  wz_offset(3) <= '1' when (unsigned(i_data)+3 = unsigned(input_addr)) else '0'; --WZE Offset 3
  
  wz_base      <= previous_address(2 downto 0);                                  --WZ Base! Qua prendo i 3 bit del WZ_BASE
  wz_match     <= '1' when (wz_offset /= "0000") else '0';                       --WZ trovato! Trovando Se ADDR cade in un WZ,allora wz_offset/="0000"

  --I registri interni.
  registers_ps : process(i_clk) --Dichiaro il processo e metto come sensibility list solo il segnale di CLOCK
  begin
    if rising_edge(i_clk) then --Potevo usare i_clk'event and i_clk='1'
      if (i_rst = '1') then --Reset Sincrono.Si poteva usare anche uno Asincrono.Quindi se il RESET e' su 1,non si puo andare da nessuna parte
        current_state    <= s0; --Rimango dove sto,nello stato iniziale
        previous_address <= (others => '0'); --L'indirizzo letto rimane quello da 16 bit tutti settati a 0
        input_addr       <= (others => '0'); --Anche qua uguale
      else

        current_state    <= next_state; --Aggiorna lo stato della macchina.Vai da S0 in qualch'altro stato
        previous_address <= address;    --Riscrivi l'indirizzo appena letto con quello attuale appena mandato alla RAM

        if (current_state = s1) then --Salva l'indirizzo di ingresso. Ci servira' la codifica di questo poi!
          input_addr <= i_data(6 downto 0);
        end if;

      end if;
    end if;
  end process;

  --Ho preferito usare una macchina di Mealy. Infatti l'output dipende dagli ingressi.
  outputs_ps : process(current_state, i_start, wz_match, previous_address, wz_base, wz_offset, input_addr)
  begin
    case current_state is --Mi metto a fare un case per apportare tutti i cambiamenti che avvengono quando ci si trova da uno stato all'altro.
      when s0 => --Aspetta per ready, poi leggi l'indirizzo 8 della RAM. Questo e' l'indirizzo di ingresso (input).

        if (i_start = '1') then --Leggi l'indirizzo 8 della RAM.
          enable  <= '1'; --Attiviamo la RAM
          write   <= '0';
          address <= x"0008"; --valore esadecimale a 16bit
          done    <= '0';
          dout    <= x"00"; --valore esadecimale a 8 bit del segnale dout
        else --Idle.Infatti lascia tutto com'era.Tanto finche non diventera' il segnale i_start='1' , non si potra iniziare.
          enable  <= '0';
          write   <= '0';
          address <= x"0000";
          done    <= '0';
          dout    <= x"00";
        end if;

      when s1 => --Settiamo l'indirizzo pari a 0 e leggiamo. QUesto sarebbe il primo indirizzo WZ base.
        enable  <= '1';
        write   <= '0';
        address <= x"0000";
        done    <= '0';
        dout    <= x"00";

      when s2 => --Se qua wz_match='1', allora scriviamo la risposta. Altrimenti, incrementiamo l'indirizzo e andiamo avanti.

        if (wz_match = '1') then --Codifica di WZ avvenuta con successo!, Scriviamo l'indirizzo 9 codificato della RAM.
          enable  <= '1';
          write   <= '1'; --Addesso possiamo anche scrivere!!!
          address <= x"0009"; --Stiamo infatti lavorando sull'indirizzo 9
          done    <= '0';
          dout    <= "1"&wz_base&wz_offset; --Qua va fatto il concatenimato di 1+3+4 bit
        elsif (previous_address = x"0007") then --Se invece no,scriviamo l'indirizzo 9 della RAM concatenando semplicement lo 0 con input_addr.
          enable  <= '1';
          write   <= '1';
          address <= x"0009";
          done    <= '0';
          dout    <= "0"&input_addr;
        else --Oppure altrimenti,leggiamo tutti gli indirizzi WZ Base sperando che alla fine uno vada bene!.
          enable  <= '1';
          write   <= '0';
          address <= std_logic_vector(unsigned(previous_address)+1);
          done    <= '0';
          dout    <= x"00";
        end if;

      when s3 => --Ultimo stato! Raggiunto questo abbiamo raggiunto l'obiettivo!!!.
        if (i_start = '1') then--Se vedi che il segnale START e' ancora posto a '1' allora attiva il segnale done per segnalare la fine dell'elaborazione
          enable  <= '0';
          write   <= '0';
          address <= x"0000";
          done    <= '1';
          dout    <= x"00";
        else --E infine prendiamo anche il caso quando done diventa 0 perche' senno non riparte tutto da zero.
          enable  <= '0';
          write   <= '0';
          address <= x"0000";
          done    <= '0';
          dout    <= x"00";
        end if;          

      when others => --Messo per sicurezza,anche perche' non dovrebbe mai succedere visto che tutti i casi sono stati presi in considerazione.
        enable  <= '0';
        write   <= '0';
        address <= x"0000";
        done    <= '1';
        dout    <= x"00";
    end case;
  end process;

  --Ultimo processo che verra' usato per decidere da quale stato a quale,si arrivera'!.
  next_state_ps : process(current_state, i_start, wz_match, previous_address) --Sensitivity list del processo.
  begin
    case current_state is

      when s0 => --Stai in questo stato finche i_start non diventa uno

        if (i_start = '1') then
          next_state <= s1;
        else --Idle.Stai dove ti trovavi
          next_state <= s0;
        end if;

      when s1 => 
      next_state <= s2; --Leggi l'indirizzo 8,perche' e' quello che dobbiamo codificare alla fine

      when s2 => --Andiamo avanti a leggere l'indirizzo WZ finche non troviamo riscontro in un WZ base oppure arriviamo alla fine.
        if (wz_match = '1') or (previous_address = x"0007") then --Se troviamo un wz base oppure no si va nello stato successivo,altrimenti si tenta fino alla fine
          next_state <= s3;
        else
          next_state <= s2;
        end if;

      when s3 => --Tutto fatto!Ora aspettiamo il segnale done, e poi per il segnale i_start='0'. E' un modo per dire che e' finita questa elaborazione!
        if (i_start = '0') then
          next_state <= s0;
        else
          next_state <= s3;
        end if;

      when others => 
      next_state <= s0; --Non dovrebbe mai accadere.Messo soltanto per sicurezza!

    end case;
  end process;

end FSM;