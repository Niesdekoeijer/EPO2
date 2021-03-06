library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity controller is
	port (
		clk                : in std_logic;
		reset              : in std_logic;

		sensor_l           : in std_logic;
		sensor_m           : in std_logic;
		sensor_r           : in std_logic;

		count_in           : in std_logic_vector (19 downto 0);
		override_vector    : in std_logic_vector (3 downto 0);
		override           : in std_logic;

		count_reset        : out std_logic;

		motor_l_reset      : out std_logic;
		motor_l_direction  : out std_logic;
		motor_l_speed      : out std_logic;

		motor_r_reset      : out std_logic;
		motor_r_direction  : out std_logic;
		motor_r_speed      : out std_logic
	
	);

end entity controller;

architecture behavioural of controller is

	type controller_state is (read_sensor, drive_motor_forward, drive_motor_fastleft, drive_motor_left, 
	drive_motor_fastright, drive_motor_right, drive_motor_left90, drive_motor_right90, drive_motor_backward, stop_motor);
	signal state, new_state : controller_state;
	signal sensor : std_logic_vector(2 downto 0);

begin
	sensor(0) <= sensor_r;
	sensor(1) <= sensor_m;
	sensor(2) <= sensor_l;

	process (clk)
begin
	if (rising_edge(clk)) then
		if (reset = '1' or unsigned(count_in) = 999999) then
			state <= read_sensor;
			count_reset <= '1';
		else
			state <= new_state;
			count_reset <= '0';
		end if;
	end if;
end process;

process (state, count_in, sensor, override, override_vector)
begin
	new_state <= state;
	case state is
		when read_sensor => 
			motor_r_reset <= '1';
			motor_l_reset <= '1';
			motor_l_direction <= '1'; -- moet iets zijn
			motor_r_direction <= '1';
			motor_r_speed <= '1';
			motor_l_speed <= '1';

			if (override = '0') then
				case sensor is
					when "000" => new_state <= drive_motor_forward;
					when "111" => new_state <= drive_motor_forward;
					when "010" => new_state <= drive_motor_forward;
					when "101" => new_state <= drive_motor_forward;
					when "100" => new_state <= drive_motor_right;
					when "110" => new_state <= drive_motor_fastright;
					when "001" => new_state <= drive_motor_left;
					when "011" => new_state <= drive_motor_fastleft;
					when others => new_state <= read_sensor;
				end case;
			else
				case override_vector is
					when "0001" => new_state <= drive_motor_forward;
					when "0010" => new_state <= drive_motor_right;
					when "0011" => new_state <= drive_motor_fastright;
					when "0100" => new_state <= drive_motor_right90;
					when "0101" => new_state <= drive_motor_left;
					when "0110" => new_state <= drive_motor_fastleft;
					when "0111" => new_state <= drive_motor_left90;
					when "1000" => new_state <= drive_motor_backward;
					when "0000" => new_state <= stop_motor;
					when others => new_state <= read_sensor;
					
				end case;
			end if;

		when drive_motor_forward => 
			motor_r_speed <= '1';
			motor_l_speed <= '1';
			motor_r_reset <= '0';
			motor_l_reset <= '0';
			motor_l_direction <= '1';
			motor_r_direction <= '0';

			new_state <= drive_motor_forward;

		when drive_motor_right => 
			motor_r_direction <= '0';
			motor_l_direction <= '1';
			motor_r_speed <= '0';
			motor_l_speed <= '1';
			motor_r_reset <= '0';
			motor_l_reset <= '0';

			new_state <= drive_motor_right;

		when drive_motor_fastright => 
			motor_r_direction <= '1';
			motor_l_direction <= '1';
			motor_r_speed <= '0';
			motor_l_speed <= '1';
			motor_r_reset <= '0';
			motor_l_reset <= '0';

			new_state <= drive_motor_fastright;

		when drive_motor_left => 
			motor_r_direction <= '0';
			motor_l_direction <= '1';
			motor_r_speed <= '1';
			motor_l_speed <= '0';
			motor_r_reset <= '0';
			motor_l_reset <= '0';

			new_state <= drive_motor_left;

		when drive_motor_fastleft => 

			motor_r_direction <= '0';
			motor_l_direction <= '0';
			motor_r_speed <= '1';
			motor_l_speed <= '0';
			motor_r_reset <= '0';
			motor_l_reset <= '0';

			new_state <= drive_motor_fastleft;

		when drive_motor_left90 => 

			motor_r_direction <= '0';
			motor_l_direction <= '0';
			motor_r_speed <= '1';
			motor_l_speed <= '1';
			motor_r_reset <= '0';
			motor_l_reset <= '0';

			new_state <= drive_motor_left90;

		when drive_motor_right90 => 

			motor_r_direction <= '1';
			motor_l_direction <= '1';
			motor_r_speed <= '1';
			motor_l_speed <= '1';
			motor_r_reset <= '0';
			motor_l_reset <= '0';

			new_state <= drive_motor_right90;

		when drive_motor_backward => --als slow
			motor_r_speed <= '0';
			motor_l_speed <= '0';
			motor_r_reset <= '0';
			motor_l_reset <= '0';
			motor_l_direction <= '1';
			motor_r_direction <= '0';
			
		when stop_motor =>
			motor_r_speed <= '0'; 
			motor_l_speed <= '0';
			motor_r_reset <= '1'; -- Eventueel deze uit zetten, zodat hij langzaam achteruit rijd (rem).
			motor_l_reset <= '1';
			motor_l_direction <= '0';
			motor_r_direction <= '1';

			new_state <= stop_motor;
	end case;
end process;



end architecture behavioural;
