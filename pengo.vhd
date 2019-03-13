--
-- A simulation model of Pengo hardware
-- Copyright (c) MikeJ - January 2006
-- Copyright (c) Sorgelig - 2017
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- You are responsible for any legal issues arising from your use of this code.
--
-- The latest version of this file can be found at: www.fpgaarcade.com
--
-- Email pacman@fpgaarcade.com
--
-- Revision list
--
-- version 006 Refactoring, 8 sprites support by Sorgelig
-- version 005 Papilio release by Jack Gassett
-- version 004 spartan3e release
-- version 003 Jan 2006 release, general tidy up
-- version 002 optional vga scan doubler
-- version 001 initial release
--
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_unsigned.all;
  use ieee.numeric_std.all;

entity PENGO is
	generic(
		eight_sprites : boolean := false
	);
	port (
		O_VIDEO_R  : out std_logic_vector(2 downto 0);
		O_VIDEO_G  : out std_logic_vector(2 downto 0);
		O_VIDEO_B  : out std_logic_vector(1 downto 0);
		O_HSYNC    : out std_logic;
		O_VSYNC    : out std_logic;
		O_HBLANK   : out std_logic;
		O_VBLANK   : out std_logic;
		--
		O_AUDIO    : out std_logic_vector(7 downto 0);
		--
		in0        : in  std_logic_vector(7 downto 0);
		in1        : in  std_logic_vector(7 downto 0);
		dipsw1     : in  std_logic_vector(7 downto 0);
		dipsw2     : in  std_logic_vector(7 downto 0);
		--
		dn_addr    : in  std_logic_vector(15 downto 0);
		dn_data    : in  std_logic_vector(7 downto 0);
		dn_wr      : in  std_logic;
		--
		RESET      : in  std_logic;
		CLK        : in  std_logic;
		ENA_6      : in  std_logic
	);
end;

architecture RTL of PENGO is


	-- timing
	signal hcnt             : std_logic_vector(8 downto 0) := "010000000"; -- 80
	signal vcnt             : std_logic_vector(8 downto 0) := "011111000"; -- 0F8

	signal do_hsync         : boolean;
	signal hsync            : std_logic;
	signal vsync            : std_logic;
	signal hblank           : std_logic;
	signal vblank           : std_logic := '1';

	-- cpu
	signal cpu_m1_l         : std_logic;
	signal cpu_mreq_l       : std_logic;
	signal cpu_iorq_l       : std_logic;
	signal cpu_rd_l         : std_logic;
	signal cpu_rfsh_l       : std_logic;
	signal cpu_int_l        : std_logic := '1';
	signal cpu_addr         : std_logic_vector(15 downto 0);
	signal cpu_data_out     : std_logic_vector(7 downto 0);
	signal cpu_data_in      : std_logic_vector(7 downto 0);

	signal rom_data         : std_logic_vector(7 downto 0);
	signal program_rom      : std_logic_vector(7 downto 0);
	signal sync_bus_cs_l    : std_logic;

	signal control_reg      : std_logic_vector(7 downto 0);
	--
	signal sync_bus_db      : std_logic_vector(7 downto 0);
	signal sync_bus_r_w_l   : std_logic;
	signal sync_bus_wreq_l  : std_logic;
	signal sync_bus_stb     : std_logic;

	signal cpu_vec_reg      : std_logic_vector(7 downto 0);
	signal sync_bus_reg     : std_logic_vector(7 downto 0);

	signal hp               : std_logic_vector ( 4 downto 0);
	signal vp               : std_logic_vector ( 4 downto 0);
	signal ram_cs           : std_logic;
	signal ram_data         : std_logic_vector(7 downto 0);
	signal vram_data        : std_logic_vector(7 downto 0);
	signal sprite_xy_data   : std_logic_vector(7 downto 0);
	signal vram_addr        : std_logic_vector(11 downto 0);

	signal iodec_spr_l      : std_logic;
	signal iodec_out_l      : std_logic;
	signal iodec_wdr_l      : std_logic;
	signal iodec_sn1_l      : std_logic;
	signal iodec_sn2_l      : std_logic;
	signal iodec_in0_l      : std_logic;
	signal iodec_in1_l      : std_logic;
	signal iodec_dipsw1_l   : std_logic;
	signal iodec_dipsw2_l   : std_logic;

	-- watchdog
	signal watchdog_cnt     : std_logic_vector(3 downto 0);
	signal watchdog_reset_l : std_logic;

begin
  
--
-- video timing
--
p_hvcnt : process
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then
		if hcnt = "111111111" then
			hcnt <= "010000000"; -- 080
		else
			hcnt <= hcnt +"1";
		end if;
		-- hcnt 8 on circuit is 256H_L
		if do_hsync then
			if vcnt = "111111111" then
				vcnt <= "011111000"; -- 0F8
			else
				vcnt <= vcnt +"1";
			end if;
		end if;
	end if;
end process;

vsync <= not vcnt(8);
do_hsync <= (hcnt = "010101111"); -- 0AF

p_sync : process
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then

		if (hcnt = "010001111") and not eight_sprites then -- 08F
			hblank <= '1';
		elsif (hcnt = "011101111") and not eight_sprites then
			hblank <= '0'; -- 0EF
		elsif (hcnt = "111111111") and eight_sprites then
			hblank <= '1';
		elsif (hcnt = "011111111") and eight_sprites then
			hblank <= '0';
		end if;

		if do_hsync then
			hsync <= '1';
		elsif (hcnt = "011001111") then -- 0CF
			hsync <= '0';
		end if;

		if do_hsync then
			if (vcnt = "111101111") then -- 1EF
				vblank <= '1';
			elsif (vcnt = "100001111") then -- 10F
				vblank <= '0';
			end if;
		end if;
	end if;
end process;

--
-- cpu
--
p_irq_req_watchdog : process
	variable rising_vblank : boolean;
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then
		rising_vblank := do_hsync and (vcnt = "111101111"); -- 1EF

		if (control_reg(0) = '0') then
			cpu_int_l <= '1';
		elsif rising_vblank then -- 1EF
			cpu_int_l <= '0';
		end if;

		-- watchdog 8c
		-- note sync reset
		if (reset = '1') then
			watchdog_cnt <= "1111";
		elsif (iodec_wdr_l = '0') then
			watchdog_cnt <= "0000";
		elsif rising_vblank then
			watchdog_cnt <= watchdog_cnt + "1";
		end if;

		--watchdog_reset_l <= not reset;

		watchdog_reset_l <= '1';
		if (watchdog_cnt = "1111") then
			watchdog_reset_l <= '0';
		end if;
	end if;
end process;

u_cpu : entity work.T80sed
port map
(
	RESET_n => watchdog_reset_l and (not reset),
	CLK_n   => clk,
	CLKEN   => hcnt(0) and ena_6,
	WAIT_n  => sync_bus_wreq_l,
	INT_n   => cpu_int_l,
	NMI_n   => '1',
	BUSRQ_n => '1',
	M1_n    => cpu_m1_l,
	MREQ_n  => cpu_mreq_l,
	IORQ_n  => cpu_iorq_l,
	RD_n    => cpu_rd_l,
	WR_n    => open,
	RFSH_n  => cpu_rfsh_l,
	HALT_n  => open,
	BUSAK_n => open,
	A       => cpu_addr,
	DI      => cpu_data_in,
	DO      => cpu_data_out
);

-- rom     0x0000 - 0x3FFF
-- syncbus 0x4000 - 0x7FFF
sync_bus_cs_l   <= '0' when cpu_mreq_l = '0' and cpu_rfsh_l = '1' and cpu_addr(15) = '1' else '1';
sync_bus_wreq_l <= '0' when sync_bus_cs_l = '0' and hcnt(1) = '1' and cpu_rd_l = '0' else '1';
sync_bus_stb    <= '0' when sync_bus_cs_l = '0' and hcnt(1) = '0' else '1';
sync_bus_r_w_l  <= '0' when sync_bus_stb  = '0' and cpu_rd_l = '1' else '1';

--
-- sync bus custom ic
--
p_sync_bus_reg : process
begin
	wait until rising_edge(clk);
	if (ena_6 = '1') then
		-- register on sync bus module that is used to store interrupt vector
		if (cpu_iorq_l = '0') and (cpu_m1_l = '1') then
			cpu_vec_reg <= cpu_data_out;
		end if;

		-- read holding reg
		if (hcnt(1 downto 0) = "01") then
			sync_bus_reg <= cpu_data_in;
		end if;
	end if;
end process;


-- WRITE
-- sn1_l    0x9000 - 0x900F voice 1,2,3 waveform
-- sn2_l    0x9010 - 0x901F x50 wr voice 1,2,3 freq/vol
-- spr_l    0x9020 - 0x902F sprites
-- out_l    0x9040 - 0x904F control space
-- wdr_l    0x9070 - 0x907F watchdog reset
iodec_sn1_l <= '0' when sync_bus_r_w_l = '0' and cpu_addr(15 downto 4) = X"900" else '1';
iodec_sn2_l <= '0' when sync_bus_r_w_l = '0' and cpu_addr(15 downto 4) = X"901" else '1';
iodec_spr_l <= '0' when sync_bus_r_w_l = '0' and cpu_addr(15 downto 4) = X"902" else '1';
iodec_out_l <= '0' when sync_bus_r_w_l = '0' and cpu_addr(15 downto 4) = X"904" else '1';
iodec_wdr_l <= '0' when sync_bus_r_w_l = '0' and cpu_addr(15 downto 4) = X"907" else '1';

-- READ
-- dipsw2_l 0x9000 - 0x903F dip switch 2
-- dipsw1_l 0x9040 - 0x907F dip switch 1
-- in1_l    0x9080 - 0x90BF in port 1
-- in0_l    0x90C0 - 0x90FF in port 0
iodec_dipsw2_l <= '0' when sync_bus_r_w_l = '1' and cpu_addr(15 downto 6) = X"90"&"00" else '1';
iodec_dipsw1_l <= '0' when sync_bus_r_w_l = '1' and cpu_addr(15 downto 6) = X"90"&"01" else '1';
iodec_in1_l    <= '0' when sync_bus_r_w_l = '1' and cpu_addr(15 downto 6) = X"90"&"10" else '1';
iodec_in0_l    <= '0' when sync_bus_r_w_l = '1' and cpu_addr(15 downto 6) = X"90"&"11" else '1';

p_control_reg : process
begin
	-- 8 bit addressable latch 7K
	-- (made into register)

	-- 0 Interrupt ena
	-- 1 Sound ena    
	-- 2 PS1          
	-- 3 Flip         
	-- 4 Coin 1 meter
	-- 5 Coin 2 meter
	-- 6 PS2          
	-- 7 PS3          

	wait until rising_edge(clk);
	if (ena_6 = '1') then
		if (watchdog_reset_l = '0') then
			control_reg <= (others => '0');
		elsif (iodec_out_l = '0') then
			control_reg(to_integer(unsigned(cpu_addr(2 downto 0)))) <= cpu_data_out(0);
		end if;
	end if; 
end process;

cpu_data_in <=	cpu_vec_reg  when (cpu_iorq_l = '0') and (cpu_m1_l = '0') else 
					sync_bus_reg when sync_bus_wreq_l = '0'                   else
					program_rom  when cpu_addr(15) = '0'                      else
					in0          when iodec_in0_l = '0'                       else
					in1          when iodec_in1_l = '0'                       else
					dipsw1       when iodec_dipsw1_l = '0'                    else
					dipsw2       when iodec_dipsw2_l = '0'                    else
					ram_data;

u_program_rom : work.dpram generic map (15,8)
port map
(
	clock_a   => clk,
	wren_a    => dn_wr and (not dn_addr(15)),
	address_a => dn_addr(14 downto 0),
	data_a    => dn_data,

	clock_b   => clk,
	address_b => cpu_addr(14 downto 0),
	q_b       => rom_data
);

-- Sega ROM descrambler adapted from MAME segacrpt.c source code
u_sega_decode : entity work.sega_decode
port map (
	I_CK     => clk,
	I_DEC    => '1',
	I_A(6)   => cpu_m1_l,
	I_A(5)   => cpu_addr(12),
	I_A(4)   => cpu_addr(8),
	I_A(3)   => cpu_addr(4),
	I_A(2)   => cpu_addr(0),
	I_A(1)   => rom_data(5),
	I_A(0)   => rom_data(3),
	I_D      => rom_data,
	O_D      => program_rom
);

ram_cs <= '1' when cpu_addr(15 downto 12) = X"8" else '0';

u_rams : work.dpram generic map (12,8)
port map
(
	clock_a   => clk,
	enable_a  => ena_6,
	wren_a    => not sync_bus_r_w_l and ram_cs,
	address_a => cpu_addr(11 downto 0),
	data_a    => cpu_data_out, -- cpu only source of ram data
	q_a       => ram_data,

	clock_b   => clk,
	address_b => vram_addr(11 downto 0),
	q_b       => vram_data
);

--
-- video subsystem
--

-- vram addr custom ic
hp <= hcnt(7 downto 3) when control_reg(3) = '0' else not hcnt(7 downto 3);
vp <= vcnt(7 downto 3) when control_reg(3) = '0' else not vcnt(7 downto 3);
vram_addr <= '0' & hcnt(2) & vp & hp when hcnt(8)='1' else
             x"FF" & hcnt(6 downto 4) & hcnt(2) when hblank = '1' else
             '0' & hcnt(2) & hp(3) & hp(3) & hp(3) & hp(3) & hp(0) & vp;

sprite_xy_ram : work.dpram generic map (4,8)
port map
(
	clock_a   => CLK,
	enable_a  => ENA_6,
	wren_a    => not iodec_spr_l,
	address_a => cpu_addr(3 downto 0),
	data_a    => cpu_data_out,

	clock_b   => CLK,		
	address_b => vram_addr(3 downto 0),
	q_b       => sprite_xy_data
);

u_video : entity work.PENGO_VIDEO
port map
(
	I_HCNT    => hcnt,
	I_VCNT    => vcnt,
	I_PS      => control_reg(7) & control_reg(6) & control_reg(2),

	--
	vram_data => vram_data,
	sprite_xy => sprite_xy_data,
	--
	I_HBLANK  => hblank,
	I_VBLANK  => vblank,
	I_FLIP    => control_reg(3),
	O_HBLANK  => O_HBLANK,
	--
	dn_addr   => dn_addr,
	dn_data   => dn_data,
	dn_wr     => dn_wr,
	--
	O_RED     => O_VIDEO_R,
	O_GREEN   => O_VIDEO_G,
	O_BLUE    => O_VIDEO_B,
	--
	ENA_6     => ena_6,
	CLK       => clk
);

O_HSYNC   <= hSync;
O_VSYNC   <= vSync;
O_VBLANK  <= vblank;

--
--
-- audio subsystem
--
u_audio : entity work.PACMAN_AUDIO
port map (
	I_HCNT        => hcnt,
	--
	I_AB          => cpu_addr(11 downto 0),
	I_DB          => cpu_data_out,
	--
	I_WR1_L       => iodec_sn2_l,
	I_WR0_L       => iodec_sn1_l,
	I_SOUND_ON    => control_reg(1),
	--
	dn_addr   => dn_addr,
	dn_data   => dn_data,
	dn_wr     => dn_wr,
	--		
	O_AUDIO       => O_AUDIO,
	ENA_6         => ena_6,
	CLK           => clk
);

end RTL;
