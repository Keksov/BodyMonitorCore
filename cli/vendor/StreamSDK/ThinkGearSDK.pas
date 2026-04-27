unit ThinkGearSDK;

{$mode objfpc}{$H+}

interface

const
    TG_MAX_CONNECTION_HANDLES = 128;

    TG_BAUD_1200 = 1200;
    TG_BAUD_2400 = 2400;
    TG_BAUD_4800 = 4800;
    TG_BAUD_9600 = 9600;
    TG_BAUD_57600 = 57600;
    TG_BAUD_115200 = 115200;

    TG_STREAM_PACKETS = 0;
    TG_STREAM_FILE_PACKETS = 2;

    TG_DATA_POOR_SIGNAL = 1;
    TG_DATA_ATTENTION = 2;
    TG_DATA_MEDITATION = 3;
    TG_DATA_RAW = 4;
    TG_DATA_DELTA = 5;
    TG_DATA_THETA = 6;
    TG_DATA_ALPHA1 = 7;
    TG_DATA_ALPHA2 = 8;
    TG_DATA_BETA1 = 9;
    TG_DATA_BETA2 = 10;
    TG_DATA_GAMMA1 = 11;
    TG_DATA_GAMMA2 = 12;
    MWM15_DATA_FILTER_TYPE = 49;

    MWM15_FILTER_TYPE_50HZ = 4;
    MWM15_FILTER_TYPE_60HZ = 5;

function    TG_GetVersion(): Integer; cdecl; external 'thinkgear64.dll';
function    TG_GetNewConnectionId(): Integer; cdecl; external 'thinkgear64.dll';

function    TG_SetStreamLog(aConnectionId: Integer; const aFilename: PAnsiChar): Integer; cdecl; external 'thinkgear64.dll';
function    TG_SetDataLog(aConnectionId: Integer; const aFilename: PAnsiChar): Integer; cdecl; external 'thinkgear64.dll';
function    TG_WriteStreamLog(aConnectionId: Integer; aInsertTimestamp: Integer; const aMsg: PAnsiChar): Integer; cdecl; external 'thinkgear64.dll';
function    TG_WriteDataLog(aConnectionId: Integer; aInsertTimestamp: Integer; const aMsg: PAnsiChar): Integer; cdecl; external 'thinkgear64.dll';

function    TG_Connect(aConnectionId: Integer; const aSerialPortName: PAnsiChar; aSerialBaudrate: Integer; aSerialDataFormat: Integer): Integer; cdecl; external 'thinkgear64.dll';
function    TG_ReadPackets(aConnectionId: Integer; aNumPackets: Integer): Integer; cdecl; external 'thinkgear64.dll';
function    TG_GetValueStatus(aConnectionId: Integer; aDataType: Integer): Integer; cdecl; external 'thinkgear64.dll';
function    TG_GetValue(aConnectionId: Integer; aDataType: Integer): Single; cdecl; external 'thinkgear64.dll';

function    TG_SendByte(aConnectionId: Integer; aB: Integer): Integer; cdecl; external 'thinkgear64.dll';
function    TG_SetBaudrate(aConnectionId: Integer; aSerialBaudrate: Integer): Integer; cdecl; external 'thinkgear64.dll';
function    TG_EnableAutoRead(aConnectionId: Integer; aEnable: Integer): Integer; cdecl; external 'thinkgear64.dll';

procedure   TG_Disconnect(aConnectionId: Integer); cdecl; external 'thinkgear64.dll';
procedure   TG_FreeConnection(aConnectionId: Integer); cdecl; external 'thinkgear64.dll';

function    MWM15_getFilterType(aConnectionId: Integer): Integer; cdecl;
function    MWM15_setFilterType(aConnectionId: Integer; aFilterType: Integer): Integer; cdecl;

implementation

uses
    Windows;

type
    TMWM15GetFilterType = function(aConnectionId: Integer): Integer; cdecl;
    TMWM15SetFilterType = function(aConnectionId: Integer; aFilterType: Integer): Integer; cdecl;

var
    MWM15GetFilterTypeProc: TMWM15GetFilterType;
    MWM15SetFilterTypeProc: TMWM15SetFilterType;

function getOptionalThinkGearProc(const aProcName: PAnsiChar): Pointer;
var
    moduleHandle: HMODULE;
begin
    moduleHandle := GetModuleHandleA('thinkgear64.dll');
    if moduleHandle = 0 then
        Exit(nil);

    Result := GetProcAddress(moduleHandle, aProcName);
end;

function MWM15_getFilterType(aConnectionId: Integer): Integer; cdecl;
begin
    if not Assigned(MWM15GetFilterTypeProc) then
        Exit(-1);

    Result := MWM15GetFilterTypeProc(aConnectionId);
end;

function MWM15_setFilterType(aConnectionId: Integer; aFilterType: Integer): Integer; cdecl;
begin
    if not Assigned(MWM15SetFilterTypeProc) then
        Exit(-1);

    Result := MWM15SetFilterTypeProc(aConnectionId, aFilterType);
end;

initialization
    Pointer(MWM15GetFilterTypeProc) := getOptionalThinkGearProc('MWM15_getFilterType');
    Pointer(MWM15SetFilterTypeProc) := getOptionalThinkGearProc('MWM15_setFilterType');

end.
