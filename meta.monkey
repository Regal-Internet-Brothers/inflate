Strict

Public

' Imports:
' Nothing so far.

' Constant variable(s):

' Response-code definitions:
Const INF_OK:= 0
Const INF_DONE:= 1
Const INF_DATA_ERROR:= -3
Const INF_CHKSUM_ERROR:= -4
'Const INF_DEST_OVERFLOW:= -5

' Checksum types:
Const INF_CHECKSUM_NONE:= 0
Const INF_CHECKSUM_ADLER32:= 1
Const INF_CHECKSUM_CRC32:= 2