--SSD1306_I2C_driver4:I2C全功能版
--SSD1306_I2C 串列模式只能做寫入作業 Write mode
--Co:--1=word or 0=byte mode,byte mode後不能再設回word mode
--107.01.01版

Library IEEE;						--連結零件庫
Use IEEE.std_logic_1164.all;		--引用套件
Use IEEE.std_logic_unsigned.all;	--引用套件;

--------------------------------------------------------------------------
entity  ssd1306_i2c2wdriver4 is
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
end ssd1306_i2c2wdriver4;

--------------------------------------------------------------------------
architecture Albert of ssd1306_i2c2wdriver4 is
	signal Wdata:std_logic_vector(29 downto 0);	--寫命令表
	signal Data_byte_Bf:std_logic_vector(7 downto 0);	--Data_byte
	signal CoDc_Bf:std_logic_vector(1 downto 0);--CoDo
	signal Co,Buffer_Clr,Buffer_Empty:std_logic;
	signal I2Creset,SCLs,SDAs:std_logic;		--失敗重來,SCL,SDAs->SDAout,SDAin-->SDA
	signal I:integer range 0 to 2;		 		--相位指標
	signal WN:integer range 0 to 29;			--寫命令指標
	signal PN:integer range 0 to 29;			--錯誤暫停時間
	signal RWNS:integer range 0 to 15;			--嘗試讀寫次數計數器

begin

-----------------------------------
SDA<='0' when SDAs='0' else 'Z';--SDA bus控制

--SCL<='0' when SCLs='0' else '1'; 
--介面IO:SCL,如有接提升電阻時可設成inout
SCL<='0' When SCLs='0' Else 'Z';

reLOAD<=Buffer_Empty or Buffer_Clr;

-----------------------------------
Data_in:Process(LoadCK,Reset)
Begin
If reset='0' or Buffer_Clr='1' Then
	Buffer_Empty<='0';
Elsif rising_edge(LoadCK) Then
	Data_byte_Bf<=Data_byte;
	CoDc_Bf<=CoDc;
	Buffer_Empty<='1';		--Buffer_Empty='1'表示已有資料寫入(尚未傳出)
End If;
End Process Data_in;

-----------------------------------
process(I2CCLK,RESET)
begin
	if RESET='0' then
		--      S 裝置碼        位址  /寫   ack   Control byte      ack   寫入資料    ack    P
		Wdata<='0' & "011110" & SA0 & '0' & '1' & CoDc & "000000" & '1' & Data_byte & '1' & "00";	--(0)沒用到,結束碼
		--如Co=1,則為word mode(16bit)=(Control byte +Data byte)+(Control byte +Data byte),
		--下一筆放入Wdata(10 downto 3)<=Data_byte,WN再從19起
		--如Co=0,則為byte mode(8bit)=Control byte(只有1次)+ Data byte.....,
		--下一筆放入Wdata(10 downto 3)<=Data_byte,WN再從10起
		Co<=CoDc(1);--1=word or 0=byte mode
		
		I<=0;		--設0相位
		WN<=29;		--設寫入執行點
	
		SCLs<='1';	--設I2C為閒置
		SDAs<='1';	--設I2C為閒置
		I2CS<='0';	--設無狀態
		I2CoK<='0';	--設未完成旗標
		
		RWNS<=RWN;	--嘗試讀寫次數
		PN<=29;		--錯誤暫停時間
		I2Creset<='0';	--清除重新執行旗標
		Buffer_Clr<='0';
	elsif rising_edge(I2CCLK) then
		Buffer_Clr<='0';
		if I2Cok='0' Then	--尚未完成
			--失敗再嘗試
			if I2Creset='1' then	--重新起始
				SCLs<='1';			--bus暫停
				SDAs<='1';			--bus暫停
				I<=0;WN<=29;		--錯誤回復執行點
				if PN=0 then		--暫停時間
					PN<=29;			--重設錯誤暫停時間
					I2Creset<='0';	--取消重新執行旗標
					RWNS<=RWNS-1;	--嘗試次數
					if RWNS<=1 then	--嘗試次數已用完
						I2Cok<='1';	--完成
						I2CS<='1';	--失敗
					end if;
				else
					PN<=PN-1;		--暫停時間倒數
				end if;
			else -- RW='0' --OLED串列模式只能做寫入作業
				if WN=0 then 	--結束點
					SDAs<='1';	--Stop
					I2CoK<='1';	--結束寫入(成功)
				else
					I<=I+1;			--下一相位
					case I is
						when 0 =>	--0相位
							SDAs<=Wdata(WN);--位元輸出
						when 1 =>	--1相位
							SCLs<='1';	--SCK拉高
							WN<=WN-1;	--下一bit
							if WN=20 or WN=11 or WN=2 then	--測ACK點
								if WN=20 then		--ACK載入--第一次發現ACK錯誤時才重新執行
									I2Creset<=SDA;	--讀SSD1306發出的ACK(低態:正常,高態:錯誤)
								elsif SDA='1' then	--讀SSD1306發出的ACK
									I2CoK<='1';	--結束寫入(失敗)
									I2CS<='1';	--失敗
								end If;
							end If;
						when oThers =>--2相位
							SCLs<='0';	--SCK下拉
							I<=0;		--回0相位
							if WN=1 then
								if Buffer_Empty='1' then	--下一筆已經進來
									Wdata(10 downto 3)<=Data_byte_Bf;	--下一筆載入
									Wdata(19 downto 18)<=CoDc_Bf;
									if Co='1' then	--word mode
										Co<=CoDc_Bf(1);
										WN<=19;	--新執行點
									else			--byte mode
										WN<=10;	--新執行點
									end if;
									Buffer_Clr<='1';--清除buffer
								end if;	
							end if;
						end case;
				end if;
			end if;
		end if;
	end if;
end process;

--------------------------------------------------------------
end Albert;