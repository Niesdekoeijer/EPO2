LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY override_controller IS
	-- CONSTANTES
	generic (
	CONSTANT OPERATION_DISTANCE: INTEGER := 136; --140 1; -- Minimum aantal PWM pulsen die gepasseerd moeten zijn sinds het uitvoeren van de vorige mogelijkheid van de override controller
	CONSTANT FORWARD_PWM_COUNT: INTEGER := 20;--20; -- Aantal PWM pulsen dat die in de staten forward, left, en right moet doorbrengen
	CONSTANT LEFT_PWM_COUNT: INTEGER := 35;--35;
	CONSTANT RIGHT_PWM_COUNT: INTEGER := 35;--35;
	CONSTANT TX_MIJN: std_logic_vector(7 downto 0) := "00110000";
	CONSTANT TX_GEEN_MIJN: std_logic_vector(7 downto 0) := "00110001";
	CONSTANT RELATIVE_SEND: INTEGER := 20;--20;
	CONSTANT DISTANCE_ON_RESET: unsigned := "00000010010110"--"000010010110"
	);

	PORT (
		clk, reset            : IN std_logic;
		translator_out        : IN std_logic_vector(7 DOWNTO 0);
		override_vector       : OUT std_logic_vector(3 DOWNTO 0);
		override              : OUT std_logic;
		translator_out_reset  : OUT std_logic;
		count_reset           : IN std_logic;
		sensor_l              : IN std_logic;
		sensor_m              : IN std_logic;
		sensor_r              : IN std_logic;
		tx_out		     	  : OUT std_logic_vector(7 DOWNTO 0);
		tx_send_out  	      : OUT std_logic;
		count_in           : in std_logic_vector (19 downto 0);
		
		an 					 : OUT STD_LOGIC_VECTOR (3 downto 0); -- Selectie van de led
		sseg 				 : OUT STD_LOGIC_VECTOR (7 downto 0); -- Getal dat weergegeven moet worden.
		led 				 : out STD_LOGIC_VECTOR (7 downto 0);
		mine_button 	: in std_logic
	);
END ENTITY override_controller;

ARCHITECTURE behavioural OF override_controller IS
	-- TYPES
	TYPE override_controller_states IS ( -- Mogelijkheden override controller
	read_sensor_and_listen,
	forward, backward, stop,
       	right90, right, fastright, 
	left90, left, fastleft, 
	forward_station, left_station, right_station, mine);
	TYPE station_state_type IS ( -- States gebruikt binnen de logica van de *_station staten van de override_controller_states.
	first, second, third, fourth, fifth);
	TYPE tx_state IS ( -- States gebruikt bij de transmitter
	tx_idle, tx_wait_normal, tx_wait_station, tx_send);

	TYPE prev_operation_statetype is (station, not_station);
	TYPE prev_directiontype is(left, right, forward);

	-- Controle var
	
	SIGNAL prev_operation_state, new_prev_operation_state : prev_operation_statetype;
	SIGNAL prev_direction, next_prev_direction : prev_directiontype;
	SIGNAL station_state, new_station_state : station_state_type; -- Geheugenelementen voor het bepalen van de volgende station_state
	SIGNAL override_cont_state, override_cont_new_state : override_controller_states; -- Geheugenelementen voor het bepalen van de volgende station_state
	SIGNAL tx_state_reg, tx_state_next : tx_state; -- Geheugenelementen voor het bepalen van de volgende station_state
	SIGNAL pwm_count, new_pwm_count, distance_count, new_distance_count : unsigned (13 DOWNTO 0); -- Geheugenelementen voor de pwm-tellers voor de bochten en voor de afstand lijnengevolgd
	SIGNAL pwm_count_out : std_logic_vector (13 DOWNTO 0);
	SIGNAL pwm_count_reset, distance_count_reset : std_logic; -- Resets voor de pwm-tellers.
	SIGNAL next_translator_out_reset : std_logic;
	
	--signalen voor display
	SIGNAL override_state_sseg, station_state_sseg	 : STD_LOGIC_VECTOR (7 downto 0);
	
BEGIN

PROCESS (clk, reset) -- Check op rising edge en op resets
BEGIN
	IF (rising_edge(clk)) THEN 
		IF (reset = '1') THEN
			override_cont_state <= read_sensor_and_listen; -- Zet de states in de eerste staat
			station_state <= first;
			tx_state_reg <= tx_idle;
			prev_operation_state <= not_station;
			translator_out_reset <= '0';
			prev_direction <= forward;
		ELSE
			override_cont_state <= override_cont_new_state; -- Ga naar de volgende staat op de rising edge
			station_state <= new_station_state;
			tx_state_reg <= tx_state_next;
			prev_operation_state <= new_prev_operation_state;
			translator_out_reset <= next_translator_out_reset;
			prev_direction <= next_prev_direction;
		END IF;
	END IF;
END PROCESS;

PROCESS (clk, translator_out, sensor_l, sensor_m, sensor_r, override_cont_state, pwm_count, distance_count, pwm_count_out, station_state, prev_operation_state) -- Gedrag van specefieke handelingen
BEGIN
	next_prev_direction <= prev_direction;
	next_translator_out_reset <= '0';
	new_station_state <= station_state; -- Moet een waarde hebben
	new_prev_operation_state <= prev_operation_state;
	pwm_count_reset <= '0';
	CASE override_cont_state IS 
		WHEN read_sensor_and_listen => 	-- In deze staat zal hij lijnvolgen (dwz, overide = 0) totdat een bepaalde afstand is overschreden
		       				-- EN de sensoren allemaal zwart zijn (Bij een kruispunt!)
			
			distance_count_reset <= '0'; -- De distance-teller telt gewoon door
			override_vector <= "0000"; -- Stel hij override de controller hier, dan zet hij de robot stil.
			new_station_state <= first; -- Eerste staat in de station FSM, (als het ware een reset van de FSM)
			
			

			IF (sensor_l = '0' AND sensor_m = '0' AND sensor_r = '0' AND distance_count > OPERATION_DISTANCE) THEN -- neem de lijnvolger over. 
				override <= '1'; -- TAKE ME OVER
				
				next_translator_out_reset <= '1';
				pwm_count_reset <= '1'; -- Hij komt in de override stand en mag beginnen met tellen van het aantal pwm perioden. Deze teller is voor de bochten.
				CASE translator_out IS -- Afhankelijk van het ingekomen signaal van C wordt er hier gekozen uit de juiste bocht.
					WHEN "10000000" => override_cont_new_state <= stop; -- Standaard coderingen 
					WHEN "10000001" => override_cont_new_state <= forward;
					WHEN "10000010" => override_cont_new_state <= right;
					WHEN "10000100" => override_cont_new_state <= left;
					WHEN "10001000" => override_cont_new_state <= backward;
					WHEN "11000001" => override_cont_new_state <= forward_station;
					WHEN "11000010" => override_cont_new_state <= right_station; --OMGEDRAAID MET LEFT_STATION!!!!!!!!!
					WHEN "11000100" => override_cont_new_state <= left_station;
					WHEN OTHERS => override_cont_new_state <= read_sensor_and_listen;
										next_translator_out_reset <= '0'; -- Errorcontrole op verkeerd signaal
				END CASE;
			ELSE
				override <= '0';
				pwm_count_reset <= '0'; -- pwm_count is een counter die telt per 20 ms. Zo is het aantal pwm pulsen te tellen.
				override_cont_new_state <= read_sensor_and_listen;
			END IF;
			
			IF(Mine_button = '1') THEN
				override <= '1';
				override_cont_new_state <= mine;
				next_translator_out_reset <= '1';
			end if;

	-- Dit zijn de staten voor de verschillende bochten: rechtdoor, links en rechts bij een kruising.
	-- Er zijn ook staten voor een bocht naar een station, hier zal de staat ook de bocht aan het einde van de weg maken.
	-- Aan het einde van de actie komt de override_controller weer in zijn read_sensor_and_listen staat.


		WHEN forward => --Een korte periode vooruit rijden en daarna weer over op lijnvolgen.
		next_prev_direction <= forward;
		new_prev_operation_state <= not_station;
			CASE station_state IS  
				WHEN first =>
					distance_count_reset <= '0'; -- Reset de beide tellers niet
					pwm_count_reset <= '0';
					override <= '0'; -- Gewoon lijnvolgen, hij zal automatisch recht door rijden!
					override_vector <= "0001"; -- vooruit
					override_cont_new_state <= forward; -- blijf in forward
				 
					IF (unsigned(pwm_count_out) < FORWARD_PWM_COUNT) THEN -- Zie lijst met constantes
						new_station_state <= first; -- Blijf in dezelfde staat als hij nog niet lang genoeg rechtdoor heeft gereden
					ELSE
						new_station_state <= second; -- Ga naar de volgende staat
					END IF;
				WHEN OTHERS => --second and others.
					distance_count_reset <= '1'; -- Reset de gereden afstand staat
					pwm_count_reset <= '1'; -- Reset de counter voor de handelingen
					override <= '0'; -- Lijnvolgen
					override_vector <= "0000";-- Moet iets zijn, dont care
					override_cont_new_state <= read_sensor_and_listen; -- Ga naar de begin staat

			END CASE;
			
		WHEN left => -- Voor een bepaalde tijd een bocht naar links maken en daarna weer lijnvolgen.
		next_prev_direction <= left;
		new_prev_operation_state <= not_station;
			CASE station_state IS
				WHEN first =>
					distance_count_reset <= '0'; -- OPM: Dit wordt wel vaker gedaan. Distance_count_reset wordt wel vaker niet gereset ookal wordt die niet gebruikt
					pwm_count_reset <= '0';	     -- Is hier een speciale reden voor?
					override <= '1';
					override_vector <= "0111"; -- harde bocht naar links 0111 -- zachte bocht naar links: 0101
					override_cont_new_state <= left; 

					IF (unsigned(pwm_count_out) < LEFT_PWM_COUNT) THEN
						new_station_state <= first; -- Blijf in dezelfde staat
					ELSE
						new_station_state <= second; -- Ga naar de volgende
					END IF;
				WHEN second => -- Rechtdoor rijden tot dat de linker sensor weer de lijn ziet. Dit geeft de soepelste bocht.
					distance_count_reset <= '0'; 
					pwm_count_reset <= '0';	    
					override <= '1';
					override_vector <= "0001"; -- rechtdoor
					override_cont_new_state <= left; 

					if(sensor_l = '0') then --OUD: (sensor_r = '0' AND sensor_m = '0')
						new_station_state <= third; -- ga naar volgende staat
					else
						new_station_state <= second; --blijf in dezelfde staat
					end if;
					
				WHEN OTHERS => --second and others.
					distance_count_reset <= '1'; -- Reset de gereden distance, deze hebben we zo weer nodig
					pwm_count_reset <= '1'; -- Reset de handelings pwm-teller
					override <= '0'; -- Lijnvolen
					override_vector <= "0000";-- moet iets zijn
					override_cont_new_state <= read_sensor_and_listen;

			END CASE;
	
	WHEN right => -- Voor een bepaalde periode een bocht naar rechts maken en dan weer lijnvolgen.
		next_prev_direction <= right;
		new_prev_operation_state <= not_station;
			CASE station_state IS
				WHEN first =>
					distance_count_reset <= '0';
					pwm_count_reset <= '0';
					override <= '1';
					override_vector <= "0100"; -- harde bocht naar rechts
					override_cont_new_state <= right;

					IF (unsigned(pwm_count_out) < RIGHT_PWM_COUNT) THEN
						new_station_state <= first;
					ELSE
						new_station_state <= second;
					END IF;
					
				WHEN second => -- Rechtdoor rijden tot dat de rechter sensor weer de lijn ziet. Dit geeft de soepelste bocht.
					distance_count_reset <= '0'; 
					pwm_count_reset <= '0';	    
					override <= '1';
					override_vector <= "0001"; -- rechtdoor
					override_cont_new_state <= right; 
	
					if(sensor_r = '0') then -- oud:  NOT(sensor_l = '0' AND sensor_m = '0')
						new_station_state <= third;
					else
						new_station_state <= second;
					end if;	
				
				WHEN OTHERS => --second and others.
					distance_count_reset <= '1';
					pwm_count_reset <= '1';
					override <= '0';
					override_vector <= "0000";-- moet iets zijn
					override_cont_new_state <= read_sensor_and_listen;
		
			END CASE;
			
		WHEN backward => -- Deze staat is nog niet functioneel
			IF (unsigned(pwm_count_out) < 50) THEN
				distance_count_reset <= '0';
				pwm_count_reset <= '0';
				override <= '1';
				override_vector <= "1000";
				override_cont_new_state <= backward;
		
			ELSE
				distance_count_reset <= '1';
				pwm_count_reset <= '1';
				override <= '0';
				override_vector <= "0000";-- moet iets zijn
				override_cont_new_state <= read_sensor_and_listen;
			
			END IF;

		WHEN stop =>
			IF (unsigned(pwm_count_out) < 2) THEN
				distance_count_reset <= '0';
				pwm_count_reset <= '0';
				override <= '1';
				override_vector <= "0000";
				override_cont_new_state <= stop;
		
			ELSE
				distance_count_reset <= '1';
				pwm_count_reset <= '1';
				override <= '0';
				override_vector <= "0000";-- moet iets zijn
				override_cont_new_state <= read_sensor_and_listen;
		
			END IF;


		WHEN left_station =>
			new_prev_operation_state <= station;
			distance_count_reset <= '0';
			pwm_count_reset <= '0';
			override_vector <= "1000"; -- moet iets zijn
	
			override_cont_new_state <= left_station;
			CASE station_state IS
				WHEN first => -- Gewoon de bocht naar links(gekopierd)
					distance_count_reset <= '0';
					pwm_count_reset <= '0';
					override <= '1';
					override_vector <= "0111"; -- harde bocht naar links
					override_cont_new_state <= left_station;
		
					IF (unsigned(pwm_count_out) < LEFT_PWM_COUNT) THEN
						new_station_state <= first;
					ELSE
						new_station_state <= second;
					END IF;
				WHEN second => -- De lijn terugvinden.
					distance_count_reset <= '0';
					pwm_count_reset <= '0';
					override <= '1';
					override_vector <= "0001"; -- Rechtdoor
					override_cont_new_state <= left_station;
		
					IF (sensor_r = '0' AND sensor_m = '0') THEN
						new_station_state <= THIRD;
					ELSE
						new_station_state <= second;
					END IF;
				
				WHEN third => --lijnvolgen (override = '0') zolang in ieder geval 1 van de sensoren een lijn ziet. Zo rijd hij tot het einde van de lijn (waar ze alle drie wit (='1') worden)
					override <= '0';
					IF (sensor_l = '0' OR sensor_m = '0' OR sensor_r = '0') THEN
						new_station_state <= third;
					ELSE
						new_station_state <= fourth;
					END IF;
				WHEN fourth => --Bocht maken als hij aan het einde van de lijn is. Dan geldt: sensor_l ='1' (wit). Dan 180 graden RECHTSOM draaien. De linker sensor zal als laatste weer zwart worden. Dan verder naar de volgende stap.
					override <= '1';
					override_vector <= "0100"; -- drive_motor_fastright.
					IF (sensor_l = '1') THEN
						new_station_state <= fourth;
					ELSE
						new_station_state <= fifth;
					END IF;
				WHEN fifth => -- De robot is klaar om weer lijn te volgen, hij verlaat de override stand.
					distance_count_reset <= '0'; -- In het geval dat de robot een station bezocht heeft hoeft hij niet de distance counter te resetten, omdat hij geen zwarte stip meer tegen zal komen.
					pwm_count_reset <= '1';
					override <= '0';
					override_cont_new_state <= read_sensor_and_listen;
		
					new_station_state <= first;
			END CASE;

		WHEN forward_station => -- VOORBEELD VOOR FORWARD_STATION COMMANDO.
			new_prev_operation_state <= station;
			distance_count_reset <= '0';
			pwm_count_reset <= '0';
			override_vector <= "1000"; -- moet iets zijn
		
			override_cont_new_state <= forward_station;
			CASE station_state IS
				WHEN first => -- Lijnvolgen
					override <= '0';
					IF (sensor_l = '0' OR sensor_m = '0' OR sensor_r = '0') THEN --lijnvolgen zolang in ieder geval 1 van de sensoren een lijn ziet. Zo rijd hij tot het einde van de lijn (waar ze alle drie wit (='1') worden)
						new_station_state <= first;
					ELSE
						new_station_state <= second;
					END IF;
				WHEN second => --Bocht maken als hij aan het einde van de lijn is. Dan geldt: sensor_l ='1' (wit). Dan 180 graden RECHTSOM draaien. De linker sensor zal als laatste weer zwart worden. Dan verder naar de volgende stap.
					override <= '1';
					override_vector <= "0100"; -- drive_motor_right90.
					IF (sensor_l = '1') THEN
						new_station_state <= second;
					ELSE
						new_station_state <= third;
					END IF;
				WHEN third =>
					distance_count_reset <= '0'; -- De robot is klaar om weer lijn te volgen, hij verlaat de override stand. Hij moet hier weer een signaal sturen naar de pc dat hij het volgende commando wil.
					pwm_count_reset <= '1';
					override <= '0';
					override_cont_new_state <= read_sensor_and_listen;
		
					new_station_state <= first;
				WHEN OTHERS => -- zelfde als Third
					distance_count_reset <= '0';
					pwm_count_reset <= '1';
					override <= '0';
					override_cont_new_state <= read_sensor_and_listen;
		
					new_station_state <= first;
			END CASE;

		WHEN right_station =>
			new_prev_operation_state <= station;
			distance_count_reset <= '0';
			pwm_count_reset <= '0';
			override_vector <= "1000"; -- moet iets zijn
			override_cont_new_state <= right_station;
			CASE station_state IS
				WHEN first => -- Gewoon de bocht naar rechts (gekopierd)
					distance_count_reset <= '0';
					pwm_count_reset <= '0';
					override <= '1';
					override_vector <= "0100"; -- harde bocht naar links
					override_cont_new_state <= right_station;
			
					IF (unsigned(pwm_count_out) < RIGHT_PWM_COUNT) THEN
						new_station_state <= first;
					ELSE
						new_station_state <= second;
					END IF;
				WHEN second =>
					distance_count_reset <= '0';
					pwm_count_reset <= '0';
					override <= '1';
					override_vector <= "0001"; -- Vooruit
					override_cont_new_state <= right_station;
			
					IF (sensor_l = '0' AND sensor_m = '0') THEN
						new_station_state <= THIRD;
					ELSE
						new_station_state <= second;
					END IF;
				
				WHEN third => --lijnvolgen (override = '0') zolang in ieder geval 1 van de sensoren een lijn ziet. Zo rijd hij tot het einde van de lijn (waar ze alle drie wit (='1') worden)
					override <= '0';
					IF (sensor_l = '0' OR sensor_m = '0' OR sensor_r = '0') THEN
						new_station_state <= third;
					ELSE
						new_station_state <= fourth;
					END IF;
				WHEN fourth => --Bocht maken als hij aan het einde van de lijn is. Dan geldt: sensor_l ='1' (wit). Dan 180 graden LINKSOM draaien. De linker sensor zal als laatste weer zwart worden. Dan verder naar de volgende stap.
					override <= '1';
					override_vector <= "0111"; -- drive_motor_left90.
					IF (sensor_r = '1') THEN
						new_station_state <= fourth;
					ELSE
						new_station_state <= fifth;
					END IF;
				WHEN fifth => -- De robot is klaar om weer lijn te volgen, hij verlaat de override stand.
					distance_count_reset <= '0'; -- In het geval dat de robot een station bezocht heeft hoeft hij niet de distance counter te resetten, omdat hij geen zwarte stip meer tegen zal komen.
					pwm_count_reset <= '1';
					override <= '0';
					override_cont_new_state <= read_sensor_and_listen;

					new_station_state <= first;
			END CASE;
			
		WHEN mine =>
			new_prev_operation_state <= station;
			distance_count_reset <= '0';
			pwm_count_reset <= '0';
			override_vector <= "1000"; -- moet iets zijn
			override_cont_new_state <= mine;
			CASE station_state IS
				WHEN first =>
					override <= '1';
					IF (prev_direction = forward) THEN
						override_vector <= "0100";
					ELSIF(prev_direction = right) THEN
						override_vector <= "0111";
					ELSE --prev = left
						override_vector <= "0111"; -- 
					end if;
						
					IF (sensor_l = '0' OR sensor_m = '0' OR sensor_r = '0') THEN
						new_station_state <= first;
					ELSE
						new_station_state <= second;
					END IF;
					
				
				WHEN second => --Bocht maken als hij aan het einde van de lijn is. Dan geldt: sensor_l ='1' (wit). Dan 180 graden LINKSOM draaien. De linker sensor zal als laatste weer zwart worden. Dan verder naar de volgende stap.
					override <= '1';
					IF (prev_direction = forward) THEN
						override_vector <= "0100"; --
						IF (sensor_r = '0') THEN
							new_station_state <= third;
						ELSE
							new_station_state <= second;
						END IF;
					ELSIF(prev_direction = right) THEN
						override_vector <= "0111"; -- 
						IF (sensor_l = '0') THEN
							new_station_state <= third;
						ELSE
							new_station_state <= second;
						END IF;
					ELSE --prev = left
						override_vector <= "0100"; -- 
							IF (sensor_r = '0') THEN
								new_station_state <= third;
							ELSE
								new_station_state <= second;
							END IF;
					end if;
					
					when others =>
						override <= '0';
						distance_count_reset <= '0';
						pwm_count_reset <= '1';
						override_cont_new_state <= read_sensor_and_listen;
					
						new_station_state <= first;
			
			
				end case;

		WHEN OTHERS =>
			distance_count_reset <= '0';
			pwm_count_reset <= '0';
			override <= '0';
			override_vector <= "0000";-- moet iets zijn
			override_cont_new_state <= read_sensor_and_listen;

	END CASE;
END PROCESS;


-- Counter van PWM perioden (20 ms). Wordt gebruikt voor bochten van een bepaalde lengte 
PROCESS (count_reset, pwm_count_reset, reset, clk)
BEGIN
	IF (reset = '1' OR pwm_count_reset = '1') THEN
		pwm_count <= (OTHERS => '0');
	ELSIF (rising_edge(count_reset)) THEN
		pwm_count <= new_pwm_count;
	END IF;
END PROCESS;

PROCESS (pwm_count)
BEGIN
	new_pwm_count <= pwm_count + 1;
END PROCESS;
pwm_count_out <= std_logic_vector(pwm_count);


-- Counter van PWM perioden, maar dan voor de afstandsmeting (Het stukje tussen de twee stations)
PROCESS (count_reset, distance_count_reset, reset, clk)
BEGIN
	IF (reset = '1') THEN
		distance_count <= DISTANCE_ON_RESET; -- Bij een reset doet de distance counter er niet toe, hij begint dan namelijk bij een station.
	ELSIF (distance_count_reset = '1') THEN
		distance_count <= (OTHERS => '0');
	ELSIF (rising_edge(count_reset)) THEN
		distance_count <= new_distance_count;
	END IF;
END PROCESS;

PROCESS (distance_count)
BEGIN
	new_distance_count <= distance_count + 1;
END PROCESS;


-- tx signalen. Zal versturen op het kruisen van de stip tussen de kruispunten, of bij het verschijnen in een *_station staat
PROCESS (clk, sensor_l, sensor_r, sensor_m, distance_count, distance_count_reset, override_cont_state, tx_state_reg, prev_operation_state)
BEGIN
	tx_state_next <= tx_state_reg;
	tx_out <= TX_GEEN_MIJN;
	
	if(mine_button = '1') then
		tx_out <= TX_MIJN;
		tx_state_next <= tx_send;
	end if;
		
	CASE(tx_state_reg) IS
		WHEN tx_idle => -- Wachten wachten wachten wachten....
			tx_send_out <= '0';
			IF ( override_cont_state /= read_sensor_and_listen) THEN
				tx_state_next <= tx_send;
			END IF;
		WHEN tx_send => -- stuur 1 klokpuls
			tx_send_out <= '1';
			tx_state_next <= tx_wait_normal;

		WHEN tx_wait_station => -- WORDT NU NIET GEBRUIKT
			tx_send_out <= '0';
			IF (NOT(override_cont_state = forward_station OR override_cont_state = right_station OR override_cont_state = left_station)) THEN
			tx_state_next <= tx_idle;
		end if;
		
		WHEN tx_wait_normal => -- Forceer hem om maar een keer te sturen bij normale states. Aan het einde van een handeling wordt distance_count gereset
			tx_send_out <= '0';
			IF(override_cont_state = read_sensor_and_listen) then 
				tx_state_next <= tx_idle;
			END IF;
	END CASE;
END PROCESS;


--Segmentendisplay aansturen

process(station_state_sseg, override_state_sseg, distance_count)
begin
sseg(7) <= '0'; --decimale punt uit
IF(count_in(15) = '0') THEN
	an <= "1110";
	sseg <= override_state_sseg;
ELSE
	sseg <= station_state_sseg;
	an <= "0111";
END IF;
END PROCESS; 

	with translator_out select
      override_state_sseg(7 downto 0) <=
         "01000000" when "00000000", --0 leeg
         "01111001" when "10000001", --1 vooruit
         "00100100" when "10000100", --2 links
         "00110000" when "10000010", --3 rechts
         "00011001" when "11000001", --4 voorruit station
         "00010010" when "11000100", --5 links station
         "00000010" when "11000010", --6 rechts station
         "01111000" when "10000000", --7 stop
         "00001110" when others; --f
		 
   	with station_state select
		station_state_sseg(7 downto 0) <=
         "01111001" when first, --1
         "00100100" when second, --2 
         "00110000" when third, 	--3 
         "00011001" when fourth, --4 
         "00010010" when fifth, 	--5 
         "00001110" when others; --f 

--oud: led <= (OTHERS => '1'); 
		 
process(distance_count)
begin
IF(distance_count <  18) THEN --18
	led <= "00000000";
ELSIF(distance_count < 36) THEN -- 36 operation_distance *2/8
	led <= "00000001";
ELSIF(distance_count < 54) THEN -- 54
	led <= "00000011";
ELSIF(distance_count < 72) THEN -- 72
	led <= "00000111";
ELSIF(distance_count < 90) THEN -- 90
	led <= "00001111";
ELSIF(distance_count < 108) THEN --108
	led <= "00011111";
ELSIF(distance_count < 126) THEN --126
	led <= "00111111";	
ELSIF(distance_count < operation_distance) THEN -- 144
	led <= "01111111";
ELSE
	led <= "11111111";
END IF;

END PROCESS;
END ARCHITECTURE behavioural;
