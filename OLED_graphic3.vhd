--OLED練習6 2018/7/20
--顯示數字
--左OLED：畫面由左至右填滿後顯示圖片 直到右OLED完成
--右OLED：顯示溫度和數字 下方為長條圖0~50 下個動作為全部由右至左填滿
--最後再重來
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

entity OLED_graphic3 is
	port	(	CLK:in std_logic;
				RST:in std_logic;
				--右OLED
				SCL:inout std_logic;
				SDA:inout std_logic;
				--左OLED
				SCL2:inout std_logic;
				SDA2:inout std_logic;
				--TSL2561
				TSL_SCL:inout std_logic;
				TSL_SDA:inout std_logic
				);
end OLED_graphic3;

architecture scan of OLED_graphic3 is

	component ssd1306_i2c2wdriver4 is
		port(  I2CCLK,RESET:in std_logic;				--系統時脈,系統重置
			  SA0:in std_logic;							--裝置碼位址
			  CoDc:in std_logic_vector(1 downto 0);		--Co & D/C
			  Data_byte:in std_logic_vector(7 downto 0);--資料輸入
			  reLOAD:out std_logic;						--載入旗標:0 可載入Data Byte
			  LoadCK:in std_logic;						--載入時脈
			  RWN:in integer range 0 to 15;				--嘗試讀寫次數
			  I2Cok,I2CS:buffer std_logic;				--I2Cok,CS 狀態
			  SCL:inout std_logic;						--介面IO:SCL,如有接提升電阻時可設成inout
			  SDA:inout std_logic						--SDA輸入輸出
			);
	end component ssd1306_i2c2wdriver4;
	
	component TSL2561 is
		port	(CLK:in std_logic;
				RST:in std_logic;
				ena:in std_logic;
				act_done:buffer std_logic;
				light_ready:buffer std_logic;
				data_ch0:out std_logic_vector(15 downto 0);
				data_ch1:out std_logic_vector(15 downto 0);
				data_has_read:in std_logic;
				SCL:inout std_logic;
				SDA:inout std_logic
					);
	end component TSL2561;
	
	--OLED=0:OLED初始化128x64
	signal OLED_init:integer range 0 to 63;
	signal OLED_inits:integer range 0 to 63;
	type OLED_T is array (0 to 38) of std_logic_vector(7 downto 0);
	signal OLED_RUNT:OLED_T;
	constant OLED_IT:OLED_T:=(	X"26",--0 指令長度
								X"AE",--1 display off
							
								X"D5",--2 設定除頻比及振盪頻率
								
								X"80",--3 [7:4]振盪頻率,[3:0]除頻比
								
								X"A8",--4 設COM N數
								X"3F",--5 1F:32COM(COM0~COM31 N=32),3F:64COM(COM0~COM31 N=64)
								
								X"40",--6 設開始顯示行:0(SEG0)
								
						X"E3",--X"A1",--7 non Remap(column 0=>SEG0),A1 Remap(column 127=>SEG0)
								
								X"C8",--8 掃瞄方向:COM0->COM(N-1) COM31,C8:COM(N-1) COM31->COM0
								
								X"DA",--9 設COM Pins配置
								X"12",--10 02:順配置(Disable COM L/R remap)
											--12:交錯配置(Disable COM L/R remap)
											--22:順配置(Enable COM L/R remap)
											--32:交錯配置(Enable COM L/R remap)
								
								X"81",--11 設對比
								X"EF",--12 越大越亮
								
								X"D9",--13 設預充電週期
								X"F1",--14 [7:4]PHASE2,[3:0]PHASE1
								
								X"DB",--15 設Vcomh值
								X"30",--16 00:0.65xVcc,20:0.77xVcc,30:0.83xVcc
								
								
								X"A4",--17 A4:由GDDRAM決定顯示內容,A5:全部亮(測試用)
								
								X"A6",--18 A6:正常顯示(1亮0不亮),A7反相顯示(0亮1不亮)
								
								X"D3",--19 設顯示偏移量Offset
								X"00",--20 00
								
						X"E3",--X"20",--21 設GDDRAM pointer模式
						X"E3",--X"02",--22 00:水平模式,  01:垂直模式,02:頁模式
								
								--頁模式column start address=[higher nibble,lower nibble] [00]
						X"E3",--X"00",--23 頁模式下設column start address(lower nibble):0
								
						X"E3",--X"10",--24 頁模式下設column start address(higher nibble):0
								
						X"E3",--X"B0",--25 頁模式下設Page start address
								
								X"20",--26 設GDDRAM pointer模式
								X"00",--27 00:水平模式,  01:垂直模式,02:頁模式
								
								X"21",--28 水平模式下設行範圍:
								X"00",--29 行開始位置0(Column start address)
								X"7F",--30 行結束位置127(Column end address)
								
								X"22",--31 水平模式下設頁範圍:
								X"00",--32 頁開始位置0(Page start address)
								X"07",--33 頁結束位置7(Page end address)
								
								X"A1",--34 non Remap(column 0=>SEG0),A1 Remap(column 127=>SEG0)
								
								X"8D",--35 設充電Pump
								X"14",--36 14:開啟,10:關閉
								
								X"AF",--37 display on
								X"E3" --38 nop
							);
	--OLED common signals
	signal OLED_I2CCLK:std_logic;
	signal OLED_RST:std_logic;
	signal OLED_CoDC:std_logic_vector(1 downto 0);
	signal OLED_load:std_logic;
	signal OLED_RWN:integer range 0 to 15;
	--OLED1 right
	signal OLED_data:std_logic_vector(7 downto 0);
	signal OLED_reload:std_logic;
	signal OLED_I2Cok,OLED_I2CS:std_logic;
	--OLED2 left
	signal OLED2_data:std_logic_vector(7 downto 0);
	signal OLED2_reload:std_logic;
	signal OLED2_I2Cok,OLED2_I2CS:std_logic;
	--OLED control
	signal OLED_c_RST:std_logic;
	signal OLED_c_ok:std_logic;
	signal OLED_p_RST:std_logic;
	signal OLED_p_ok:std_logic;
	signal times:integer range 0 to 2047;		--停頓時間 當=0時觸發OLED動作(更新畫面)
	--OLED GDDRAM pointers
	signal GDDRAM_col_pointer:integer range 0 to 127;
	signal GDDRAM_page:integer range 0 to 15;
	--GDDRAM
	signal GDDRAMo,GDDRAMo1:std_logic_vector(7 downto 0);
	signal GDDRAM2o,GDDRAM2o1:std_logic_vector(7 downto 0);
	signal GDD_scan:std_logic_vector(7 downto 0);
	signal GDD_bargraph:std_logic_vector(7 downto 0);
	signal GDD_image:std_logic_vector(7 downto 0);
	signal GDD_image2:std_logic_vector(7 downto 0);
	--scan signals
	signal scan_clk:std_logic;
	signal col_counter:integer range 0 to 127;	--行數128
	signal mode:std_logic_vector(1 downto 0);		--模式
	--Divider
	signal Q:std_logic_vector(26 downto 0);
	--TSL2561 signals
	signal TSL_act:std_logic;
	signal TSL_done:std_logic;
	signal TSL_data_ready:std_logic;
	signal TSL_data_ch0:std_logic_vector(15 downto 0);
	signal TSL_data_ch1:std_logic_vector(15 downto 0);
	signal TSL_data_read:std_logic;
	----OLED 128*64圖片
	type OLED_T1 is array (0 to 1023) of std_logic_vector(7 Downto 0);
	constant OLED_screenShow:OLED_T1:=
   (	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"80", X"C0", X"E0", X"70", X"38", X"18", X"18",
		X"0C", X"0C", X"0C", X"0C", X"0C", X"0C", X"0C", X"18", X"18", X"00", X"00", X"00", X"00", X"00", X"FF", X"FF",
		X"FF", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"F8", X"FF", X"FF", X"07", X"01", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"FF", X"FF",
		X"FF", X"00", X"00", X"00", X"00", X"00", X"80", X"E0", X"F8", X"78", X"1C", X"0C", X"0E", X"06", X"06", X"06",
		X"06", X"06", X"0E", X"1C", X"7C", X"F8", X"F0", X"C0", X"00", X"00", X"00", X"F0", X"F8", X"FC", X"8C", X"06",
		X"06", X"06", X"06", X"06", X"0E", X"0C", X"00", X"00", X"00", X"00", X"80", X"E0", X"F8", X"38", X"1C", X"0E",
		X"06", X"06", X"06", X"06", X"06", X"0E", X"1C", X"F8", X"F0", X"E0", X"00", X"00", X"00", X"00", X"FE", X"FE",
		X"FE", X"30", X"0C", X"06", X"06", X"06", X"0E", X"00", X"00", X"F0", X"F8", X"FC", X"8C", X"06", X"06", X"06",
		X"06", X"06", X"0E", X"0C", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"07", X"1F", X"7F", X"F8", X"E0", X"C0", X"80", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"80", X"00", X"00", X"00", X"00", X"00", X"FF", X"FF",
		X"FF", X"00", X"00", X"00", X"00", X"00", X"3F", X"7F", X"FF", X"E0", X"80", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"80", X"E0", X"FF", X"7F", X"1F", X"00", X"00", X"00", X"80", X"01", X"03", X"03", X"07",
		X"07", X"07", X"0E", X"1E", X"FC", X"F8", X"F0", X"00", X"00", X"00", X"3F", X"FF", X"FF", X"E3", X"83", X"03",
		X"03", X"03", X"03", X"03", X"03", X"03", X"03", X"03", X"83", X"03", X"00", X"00", X"00", X"00", X"FF", X"FF",
		X"FF", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"80", X"01", X"03", X"03", X"07", X"07", X"07",
		X"0E", X"1E", X"FC", X"F8", X"F0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"01", X"03", X"03", X"03", X"07",
		X"06", X"06", X"06", X"06", X"06", X"06", X"03", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"07", X"07",
		X"07", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"01", X"01", X"03", X"03", X"07", X"06", X"06", X"06",
		X"06", X"06", X"03", X"03", X"01", X"01", X"00", X"00", X"00", X"00", X"00", X"01", X"03", X"06", X"06", X"06",
		X"06", X"06", X"06", X"03", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"01", X"03", X"03", X"07",
		X"07", X"06", X"06", X"06", X"06", X"06", X"03", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"07", X"07",
		X"07", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"01", X"03", X"06", X"06", X"06", X"06", X"06",
		X"06", X"03", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
		X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
		type char is array(0 to 127) of std_logic_vector(7 downto 0);
		type chars is array(0 to 11) of char;	--0~9數字編碼 10"溫" 11"度"
		signal ROM:chars;
		signal lux:integer range 0 to 50;	--顯示數字
begin
	--1:OLED right
	--2:OLED left
	U1:ssd1306_i2c2wdriver4 port map(OLED_I2CCLK , OLED_RST , '0' , OLED_CoDC , OLED_data , OLED_reload , OLED_load , 3 , OLED_I2Cok , OLED_I2CS , SCL , SDA);
	U2:ssd1306_i2c2wdriver4 port map(OLED_I2CCLK , OLED_RST , '0' , OLED_CoDC , OLED2_data , OLED2_reload , OLED_load , 3 , OLED2_I2Cok , OLED2_I2CS , SCL2 , SDA2);
	U3:TSL2561 port map (CLK , RST , TSL_act , TSL_done , TSL_data_ready , TSL_data_ch0, TSL_data_ch1 , TSL_data_read ,  TSL_SCL , TSL_SDA);
	
	divider:process(RST,CLK)
	begin
		if RST='0' then
			Q<=(others => '0');
		elsif CLK'event and CLK='1' then
			Q<=Q+1;
		end if;
	end process divider;
	OLED_I2CCLK<=Q(3);	--Driver頻率
	scan_clk<=Q(17);		--掃描頻率
	
	scanner:process(scan_clk)
	begin
		if RST='0' then
			OLED_c_RST<='0';	--重置控制
			OLED_inits<=1;		--initialize
			mode<="00";
			col_counter<=0;
			times<=200;			--停頓時間
			
			--數字編碼	32*32
			ROM(0)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"C0", X"F0", X"78", X"1C", X"0C", X"0C",
				X"0C", X"1C", X"78", X"F0", X"C0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"7F", X"FF", X"80", X"00", X"00", X"00",
				X"00", X"00", X"80", X"FF", X"7F", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"01", X"03", X"07", X"06", X"06",
				X"06", X"07", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(1)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"30", X"38", X"18", X"18", X"FC", X"FC",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"FF", X"FF",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"06", X"06", X"06", X"06", X"07", X"07",
				X"06", X"06", X"06", X"06", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(2)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"30", X"18", X"0C", X"0C", X"0C", X"0C",
				X"0C", X"1C", X"F8", X"F0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"80", X"C0", X"60", X"30", X"18",
				X"0C", X"06", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"06", X"07", X"07", X"06", X"06", X"06", X"06",
				X"06", X"06", X"06", X"06", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(3)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"18", X"0C", X"0C", X"0C", X"0C",
				X"1C", X"F8", X"F0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"06", X"06", X"06", X"06",
				X"0D", X"0D", X"F8", X"F0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"03", X"06", X"06", X"06", X"06", X"06",
				X"07", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(4)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"C0", X"60", X"18", X"F8",
				X"F8", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"C0", X"F0", X"D8", X"CE", X"C3", X"C0", X"C0", X"C0", X"FF",
				X"FF", X"C0", X"C0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"0F",
				X"0F", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(5)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"FC", X"FC", X"0C", X"0C", X"0C",
				X"0C", X"0C", X"0C", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"03", X"03", X"03", X"03", X"03",
				X"07", X"8E", X"FE", X"F8", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"03", X"06", X"06", X"06", X"06", X"06",
				X"07", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(6)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"E0", X"70", X"38", X"1C", X"0C", X"0C", X"0C",
				X"0C", X"18", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"7F", X"FF", X"84", X"06", X"03", X"03", X"03", X"03",
				X"86", X"FE", X"F8", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"01", X"03", X"07", X"06", X"06", X"06", X"07",
				X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(7)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"0C", X"0C", X"0C", X"0C", X"0C", X"0C", X"0C", X"0C",
				X"8C", X"EC", X"3C", X"0C", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"80", X"E0", X"78", X"1E",
				X"03", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"06", X"07", X"01", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(8)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"F0", X"F8", X"1C", X"0C", X"0C",
				X"0C", X"1C", X"F8", X"F0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"E0", X"F8", X"19", X"0F", X"06", X"06",
				X"06", X"0F", X"19", X"F8", X"E0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"01", X"03", X"03", X"06", X"06", X"06",
				X"06", X"06", X"03", X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(9)(0 to 127)<=
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"E0", X"F0", X"38", X"1C", X"0C", X"0C", X"0C",
				X"1C", X"38", X"F0", X"C0", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"03", X"0F", X"0E", X"1C", X"18", X"18", X"18",
				X"08", X"C4", X"FF", X"3F", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"03", X"06", X"06", X"06", X"06", X"07",
				X"03", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(10)(0 to 127)<=	--"溫"
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"40", X"C1", X"82", X"04", X"08", X"00", X"FE", X"82", X"A2", X"9A", X"8E",
				X"92", X"A2", X"82", X"FE", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"80", X"E0", X"19", X"00", X"FC", X"04", X"04", X"FC", X"04", X"04",
				X"04", X"FC", X"04", X"04", X"FC", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"04", X"03", X"00", X"02", X"02", X"03", X"02", X"02", X"03", X"02", X"02",
				X"02", X"03", X"02", X"02", X"03", X"02", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
			ROM(11)(0 to 127)<=	--"度"
			(	X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"80", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"FE", X"02", X"12", X"12", X"12", X"FA", X"12", X"13", X"12",
				X"12", X"12", X"FA", X"12", X"12", X"12", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"80", X"F0", X"1F", X"00", X"00", X"04", X"0C", X"95", X"A5", X"C5", X"45",
				X"E5", X"A5", X"9D", X"0C", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"00", X"00", X"01", X"00", X"00", X"01", X"01", X"01", X"01", X"00", X"00", X"00", X"00",
				X"00", X"00", X"00", X"01", X"01", X"01", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00");
		elsif scan_clk'event and scan_clk='1' then
			if OLED_c_ok='1' then	--控制完成
				OLED_inits<=conv_integer(OLED_RUNT(0))+1;	--初始化完成
				times<=times-1;
				if times=0 then	--觸發
					OLED_c_RST<='0';	--RESET 更新畫面
------------------------------------------main behave
					times<=0;
					case mode is
					when "00" =>	--L to R
						if col_counter=127 then	--到底(R)
							mode<="01";
						else
							col_counter<=col_counter+1;	--右移
						end if;
					when "01" =>	--R to L
						if col_counter=0 then	--到底(L)
							mode<="00";
						else
							col_counter<=col_counter-1;	--左移
						end if;
					when others =>
						NULL;
					end case;
------------------------------------------main behave
				end if;
			else
				OLED_c_RST<='1';		--啟用控制
			end if;
		end if;
	end process scanner;
	
	x1:block		--OLED
	begin
		--128*64圖片
		GDD_image2<=OLED_screenShow(GDDRAM_col_pointer+128*GDDRAM_page);
		--上方："溫度"+數字	
		--下方：長條圖
		GDD_image<=	ROM(10)(GDDRAM_col_pointer+32*GDDRAM_page)										when GDDRAM_col_pointer<32 and GDDRAM_page<4 else
						ROM(11)(GDDRAM_col_pointer-32+32*GDDRAM_page)									when GDDRAM_col_pointer<64 and GDDRAM_col_pointer>31 and GDDRAM_page<4  else
						ROM((lux mod 100) / 10)(GDDRAM_col_pointer-64+32*GDDRAM_page)	when GDDRAM_col_pointer<96 and GDDRAM_col_pointer>63 and GDDRAM_page<4  else
						ROM(lux mod 10)(GDDRAM_col_pointer-96+32*GDDRAM_page)				when GDDRAM_col_pointer<128 and GDDRAM_col_pointer>95 and GDDRAM_page<4  else
						GDD_bargraph	when GDDRAM_page>3;
		
		GDD_bargraph<="11111111" when GDDRAM_col_pointer<=127*lux/50 else "00000000";	--0~50 將數值繪製長條圖：127*(lux/50)
		GDD_scan<="11111111" when GDDRAM_col_pointer<=col_counter else "00000000";
		with mode select	--右OLED
		GDDRAMo1<=	GDD_image when "00",
						not GDD_scan when "01",
						"00000000" when others;
		with mode select	--左OLED
		GDDRAM2o1<=	GDD_scan when "00",
						GDD_image2 when "01",
						"00000000" when others;
						
		--OLED資料輸出設定
		OLED_data<=OLED_RUNT(OLED_init) when OLED_CoDC="10" else GDDRAMo1;
		OLED2_data<=OLED_RUNT(OLED_init) when OLED_CoDC="10" else GDDRAM2o1;
		
		
		
		OLED_controller:process(CLK)
		begin
			if OLED_c_RST='0' then
				OLED_p_RST<='0';						--重置OLED_p
				OLED_c_ok<='0';						--尚未完成控制
			elsif CLK'event and CLK='1' then
				if OLED_c_ok='0' then				--尚未完成控制
					if OLED_p_RST='1' then			--已啟動OLED_p
						if OLED_p_ok='1' then		--OLED_p完成動作
							OLED_c_ok<='1';			--控制完成
						end if;
					else
						OLED_p_RST<='1';				--啟動OLED_p
					end if;
				end if;
			end if;
		end process OLED_controller;
		
		OLED_p:process(OLED_p_RST,CLK)
			variable enable:boolean;
		begin
			if OLED_p_RST='0' then
				OLED_RST<='0';							--重置driver
				OLED_RUNT<=OLED_IT;					--初始化指令表
				OLED_init<=OLED_inits;				--指令起點 若初始化完成則不執行
				GDDRAM_col_pointer<=0;				--行指標歸0
				GDDRAM_page<=0;						--頁指標歸0
				OLED_p_ok<='0';						--動作尚未完成
				enable:=true;
				OLED_CoDC<="10";						--word mode,command
			elsif CLK'event and CLK='1' then
				OLED_load<='0';
				if OLED_RUNT(0)>=OLED_init then	--initialize
					if OLED_RST='0' then
						OLED_RST<='1';					--啟動Driver
					elsif enable=true then
						OLED_init<=OLED_init+1;
						enable:=false;
					elsif OLED_reload='0' and OLED2_reload='0' then
						OLED_load<='1';
						enable:=true;
					end if;
				elsif OLED_CoDC="10" then			--初始化完成 切換
					OLED_CoDC<="01";					--byte mode,data
					enable:=true;
				elsif GDDRAM_page<=7 then			--refresh image
					if OLED_RST='0' then
						OLED_RST<='1';					--啟動Driver
						enable:=false;
					else
						if OLED_reload='0' and OLED2_reload='0' then	--都可載入資料
							if enable then
								OLED_load<='1';		--load
								enable:=false;
							else
								GDDRAM_col_pointer<=GDDRAM_col_pointer+1;	--下一行
								if GDDRAM_col_pointer=127 then	--行結尾
									GDDRAM_page<=GDDRAM_page+1;	--換頁
								end if;
								enable:=true;
							end if;
						end if;
					end if;
				else
					OLED_p_ok<=OLED_I2Cok and OLED2_I2Cok;	--動作完畢
				end if;
			end if;
		end process OLED_p;
	end block x1;
	
	--TSL2561
	x2:block
		constant K1T:std_logic_vector(15 downto 0):=X"0040";
		constant B1T:std_logic_vector(15 downto 0):=X"01F2";
		constant M1T:std_logic_vector(15 downto 0):=X"01BE";
		constant K2T:std_logic_vector(15 downto 0):=X"0080";
		constant B2T:std_logic_vector(15 downto 0):=X"0214";
		constant M2T:std_logic_vector(15 downto 0):=X"02D1";
		constant K3T:std_logic_vector(15 downto 0):=X"00C0";
		constant B3T:std_logic_vector(15 downto 0):=X"023F";
		constant M3T:std_logic_vector(15 downto 0):=X"037B";
		constant K4T:std_logic_vector(15 downto 0):=X"0100";
		constant B4T:std_logic_vector(15 downto 0):=X"0270";
		constant M4T:std_logic_vector(15 downto 0):=X"03FE";
		constant K5T:std_logic_vector(15 downto 0):=X"0138";
		constant B5T:std_logic_vector(15 downto 0):=X"016F";
		constant M5T:std_logic_vector(15 downto 0):=X"01FC";
		constant K6T:std_logic_vector(15 downto 0):=X"019A";
		constant B6T:std_logic_vector(15 downto 0):=X"00D2";
		constant M6T:std_logic_vector(15 downto 0):=X"00FB";
		constant K7T:std_logic_vector(15 downto 0):=X"029A";
		constant B7T:std_logic_vector(15 downto 0):=X"0018";
		constant M7T:std_logic_vector(15 downto 0):=X"0012";
		constant K8T:std_logic_vector(15 downto 0):=X"029A";
		constant B8T:std_logic_vector(15 downto 0):=X"0000";
		constant M8T:std_logic_vector(15 downto 0):=X"0000";
		constant shift:std_logic_vector(13 downto 0):="10000000000000";
		constant CH_SCALE:integer:=10;
		constant chscale:std_logic_vector(15 downto 0):=X"4000";	--402ms integration and gain=1x
		constant LUX_SCALE:integer:=14;
		constant RATIO_SCALE:integer:=9;
	begin
		TSL_control:
		process(RST,CLK)
		begin
			if RST='0' then
				TSL_act<='0';
			elsif rising_edge(CLK) then
				if TSL_done='1' then
					TSL_act<='1';
				else
					TSL_act<='0';
				end if;
			end if;
		end process;
		
		calculate:
		process(RST,CLK)
			variable temp:integer;
			variable lux_bf:integer;
			variable temp_data:std_logic_vector(15 downto 0);
			variable channel0:std_logic_vector(15 downto 0);
			variable channel1:std_logic_vector(15 downto 0);
			variable ratio:integer;
			variable ratio1:integer;
			variable b,m:integer;
		begin
			if RST='0' then
				TSL_data_read<='0';
				ratio:=0;
				lux<=0;
				lux_bf:=0;
				temp_data:= (others=> '0');
			elsif rising_edge(CLK) then
				if TSL_data_read='0' and TSL_data_ready='1' then
					TSL_data_read<='1';
					temp_data:=conv_std_logic_vector(conv_integer(TSL_data_ch0) * conv_integer(chscale),16);
					channel0:="0000000000" & temp_data(15 downto 10);
					temp_data:=conv_std_logic_vector(conv_integer(TSL_data_ch1) * conv_integer(chscale),16);
					channel1:="0000000000" & temp_data(15 downto 10);
					if channel0 /= 0 then
						ratio1:= conv_integer((channel1(5 downto 0) & "0000000000")) / conv_integer(channel0);
					end if;
					ratio:=conv_integer('0' & conv_std_logic_vector((ratio1+1),15));
						if ratio>=0 and ratio<=K1T then
							b:=conv_integer(B1T); m:=conv_integer(M1T);
						elsif ratio>=K1T and ratio<=K2T then
							b:=conv_integer(B2T); m:=conv_integer(M2T);
						elsif ratio>=K2T and ratio<=K3T then
							b:=conv_integer(B3T); m:=conv_integer(M3T);					
						elsif ratio>=K3T and ratio<=K4T then
							b:=conv_integer(B4T); m:=conv_integer(M4T);					
						elsif ratio>=K4T and ratio<=K5T then
							b:=conv_integer(B5T); m:=conv_integer(M5T);					
						elsif ratio>=K5T and ratio<=K6T then
							b:=conv_integer(B6T); m:=conv_integer(M6T);					
						elsif ratio>=K6T and ratio<=K7T then
							b:=conv_integer(B7T); m:=conv_integer(M7T);					
						elsif ratio>K8T then
							b:=conv_integer(B8T); m:=conv_integer(M8T);			
						end if;
						temp:=(conv_integer(channel0)*b) - (conv_integer(channel1)*m);
	--					if temp<0 then
	--						temp<=0;
	--					end if;
						temp:=temp + conv_integer(shift);
						temp_data:=conv_std_logic_vector(temp,16);
						lux_bf:=conv_integer("00000000000000" & temp_data(15 downto 14));
						lux<=lux_bf;
					else
						TSL_data_read<='0';
					end if;
			end if;
		end process;
	end block x2;






end scan;