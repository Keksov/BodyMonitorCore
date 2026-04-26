unit BleHelper;

{$mode objfpc}{$H+}

interface

uses
    SimpleBle;

const
    HR_SERVICE_UUID = '0000180d-0000-1000-8000-00805f9b34fb';

function initBleAdapter(out aAdapter: TSimpleBleAdapter;
    out aErrMsg: string): Boolean;
function uuidToString(const aUuid: TSimpleBleUuid): string;

implementation

{*******************************************************************************
* initBleAdapter
*   Loads SimpleBLE library, checks Bluetooth, returns adapter handle.
*   On failure sets aErrMsg and returns False.
*******************************************************************************}
function initBleAdapter(out aAdapter: TSimpleBleAdapter;
    out aErrMsg: string): Boolean;
begin
    Result := False;
    aAdapter := 0;
    aErrMsg := '';

    if not SimpleBleLoadLibrary() then
    begin
        aErrMsg := 'Failed to load SimpleBLE library (simpleble-c.dll).';
        Exit;
    end;

    SimpleBleLoggingSetLevel(SIMPLEBLE_LOG_LEVEL_NONE);

    if not SimpleBleAdapterIsBluetoothEnabled() then
    begin
        aErrMsg := 'Bluetooth is not enabled.';
        SimpleBleUnloadLibrary();
        Exit;
    end;

    if SimpleBleAdapterGetCount() = 0 then
    begin
        aErrMsg := 'No Bluetooth adapter found.';
        SimpleBleUnloadLibrary();
        Exit;
    end;

    aAdapter := SimpleBleAdapterGetHandle(0);
    if aAdapter = 0 then
    begin
        aErrMsg := 'Could not get Bluetooth adapter handle.';
        SimpleBleUnloadLibrary();
        Exit;
    end;

    Result := True;
end;

{*******************************************************************************
* uuidToString
*******************************************************************************}
function uuidToString(const aUuid: TSimpleBleUuid): string;
var
    i: Integer;
begin
    Result := '';
    for i := 0 to SIMPLEBLE_UUID_STR_LEN - 2 do
    begin
        if aUuid.Value[i] = #0 then
            Break;
        Result := Result + aUuid.Value[i];
    end;
end;

end.