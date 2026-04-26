unit BleComPortFinder;

{$mode objfpc}{$H+}

interface

uses
    SysUtils,
    Variants,
    ComObj,
    ActiveX;

type
    {***************************************************************************
     * TSerialDeviceInfo
     *   Information about a serial port device.
     ***************************************************************************}
    TSerialDeviceInfo = record
        DeviceID: string;
        Description: string;
        PNPDeviceID: string;
    end;

    PSerialDeviceInfoArray = ^TSerialDeviceInfoArray;
    TSerialDeviceInfoArray = array of TSerialDeviceInfo;

    {***************************************************************************
     * TBleComPortFinder
     *   Finds COM port for BLE device by MAC address or device name using WMI.
     *   Also provides enumeration of all serial devices.
     ***************************************************************************}
    TBleComPortFinder = class
    public
        class function findComPortByBleMacAddress(const aBleMacAddress: string): string;
        class function findComPortByDeviceName(const aDeviceName: string): string;
        class function listAllSerialDevices(out aDevices: TSerialDeviceInfoArray): Boolean;
    end;

implementation

uses
    LogCore;

{*******************************************************************************
* listAllSerialDevices
*   Enumerates all Win32_SerialPort devices and returns their info.
*   Returns: True if list was retrieved, False on error.
*   aDevices: array of device info records.
*******************************************************************************}
class function TBleComPortFinder.listAllSerialDevices(out aDevices: TSerialDeviceInfoArray): Boolean;
var
    hr: HRESULT;
    i: Integer;
    objWMIService: OleVariant;
    objSWbemLocator: OleVariant;
    colItems: OleVariant;
    objItem: OleVariant;
    enumVar: IEnumVARIANT;
    fetched: LongWord;
    pUnk: IUnknown;
    count: Integer;
    device: TSerialDeviceInfo;
    comInitialized: Boolean;
begin
    Result := False;
    SetLength(aDevices, 0);

    hr := CoInitialize(nil);
    comInitialized := Succeeded(hr) or (hr = S_FALSE);

    try
        try
            objSWbemLocator := CreateOleObject('WbemScripting.SWbemLocator');
            objWMIService := objSWbemLocator.ConnectServer('', 'root\CIMV2', '', '');

            colItems := objWMIService.ExecQuery('Select * from Win32_SerialPort');
            count := colItems.Count;

            if count > 0 then
            begin
                SetLength(aDevices, count);
                pUnk := IUnknown(colItems._NewEnum);
                pUnk.QueryInterface(IEnumVARIANT, enumVar);

                i := 0;
                while (enumVar.Next(1, @objItem, @fetched) = S_OK) and (i < count) do
                begin
                    try
                        device.DeviceID := string(objItem.DeviceID);
                        device.Description := string(objItem.Description);
                        device.PNPDeviceID := string(objItem.PNPDeviceID);
                        aDevices[i] := device;
                        Inc(i);
                    except
                        Inc(i);
                        Continue;
                    end;
                end;

                if i < count then
                    SetLength(aDevices, i);
            end;

            Result := True;
        except
            on E: Exception do
            begin
                TLogCore.writeErrorLine(nil,
                    Format('WMI error: %s: %s', [E.ClassName, E.Message]));
                Result := False;
            end;
        end;
    finally
        if comInitialized then
            CoUninitialize();
    end;
end;

{*******************************************************************************
* findComPortByBleMacAddress
*   Searches Win32_SerialPort for a device with BLE MAC in its PNPDeviceID.
*   aBleMacAddress format: "e0:7d:ea:e6:50:40" (with colons)
*   Returns: "COM4" or empty string if not found.
*******************************************************************************}
class function TBleComPortFinder.findComPortByBleMacAddress(const aBleMacAddress: string): string;
var
    i: Integer;
    devices: TSerialDeviceInfoArray;
    upperBleMac: string;
begin
    Result := '';
    upperBleMac := UpperCase(StringReplace(aBleMacAddress, ':', '', [rfReplaceAll]));

    if not listAllSerialDevices(devices) then
        Exit;

    for i := 0 to Length(devices) - 1 do
    begin
        if Pos(upperBleMac, UpperCase(devices[i].PNPDeviceID)) > 0 then
        begin
            Result := devices[i].DeviceID;
            Exit;
        end;
    end;
end;

{*******************************************************************************
* findComPortByDeviceName
*   Searches Win32_SerialPort for a device with name in its Description field.
*   aDeviceName: substring to search for (case-insensitive).
*   Returns: "COM4" or empty string if not found.
*******************************************************************************}
class function TBleComPortFinder.findComPortByDeviceName(const aDeviceName: string): string;
var
    i: Integer;
    devices: TSerialDeviceInfoArray;
    upperDeviceName: string;
begin
    Result := '';
    upperDeviceName := UpperCase(Trim(aDeviceName));

    if not listAllSerialDevices(devices) then
        Exit;

    for i := 0 to Length(devices) - 1 do
    begin
        if Pos(upperDeviceName, UpperCase(devices[i].Description)) > 0 then
        begin
            Result := devices[i].DeviceID;
            Exit;
        end;
    end;
end;

end.