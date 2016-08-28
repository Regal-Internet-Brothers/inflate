Strict

' Imports:
Import config

Public
	Import brl.databuffer
	
	Import regal.sizeof
	Import regal.byteorder
	Import regal.ioutil.util
	
	Import regal.hash
	'Import regal.hash.adler32
	'Import regal.hash.crc32
	
	Import meta
Private
	Import regal.util.memory
Public

' Functions:
Function Get_Short:Int(buffer:DataBuffer, index:Int) ' Short
	Return ArrayGetShort(buffer, index)
End

Function Get_Byte:Int(buffer:DataBuffer, index:Int) ' Byte
	Return (buffer.PeekByte(index) & $FF)
End

Function Set_Short:Void(buffer:DataBuffer, index:Int, value:Int) ' Short
	ArraySetShort(buffer, index, value)
End

Function Set_Byte:Void(buffer:DataBuffer, index:Int, value:Int) ' Byte
	buffer.PokeByte(index, (value & $FF))
End

' Debugging-related:

#Rem
	Function Get_Byte:Int(values:Int[], index:Int)
		Return (values[index] & $FF)
	End
	
	Function Set_Byte:Void(buffer:Int[], index:Int, value:Int)
		buffer[index] = (value & $FF)
	End
#End