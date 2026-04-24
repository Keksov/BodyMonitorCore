unit BleLogHelper;

{$mode objfpc}{$H+}

interface

uses
    SysUtils,
    LogCore,
    JsonLogWriter;

procedure writeBleScanLine(aLogger: TLogCore; const aStage: string;
    const aLevel: string; const aMessage: string);

procedure writeBleScanCountLine(aLogger: TLogCore; const aStage: string;
    const aLevel: string; const aMessage: string; aCount: Integer);

procedure writeBleDeviceInfo(aLogger: TLogCore; aIndex: Integer;
    const aMac: string; const aIdentifier: string; const aDeviceType: string;
    const aComPort: string; const aConsoleLine: string = '');

procedure writeBleDeviceError(aLogger: TLogCore; const aMac: string;
    const aMessage: string; const aConsoleLine: string = '');

implementation

{*******************************************************************************
* writeBleScanLine
*******************************************************************************}
procedure writeBleScanLine(aLogger: TLogCore; const aStage: string;
    const aLevel: string; const aMessage: string);
begin
    if aLogger <> nil then
    begin
        aLogger.pushLine('{' + jsonLogTimestamp('br') +
            ',"event":"ble_scan"' +
            ',"source":"ble"' +
            ',"level":"' + aLevel + '"' +
            ',"stage":"' + aStage + '"' +
            ',"message":"' + jsonEscape(aMessage) + '"}');
        aLogger.flush;
    end;
    TLogCore.writeConsoleLine(aLogger, aMessage);
end;

{*******************************************************************************
* writeBleScanCountLine
*******************************************************************************}
procedure writeBleScanCountLine(aLogger: TLogCore; const aStage: string;
    const aLevel: string; const aMessage: string; aCount: Integer);
begin
    if aLogger <> nil then
    begin
        aLogger.pushLine('{' + jsonLogTimestamp('br') +
            ',"event":"ble_scan"' +
            ',"source":"ble"' +
            ',"level":"' + aLevel + '"' +
            ',"stage":"' + aStage + '"' +
            ',"count":' + IntToStr(aCount) +
            ',"message":"' + jsonEscape(aMessage) + '"}');
        aLogger.flush;
    end;
    TLogCore.writeConsoleLine(aLogger, aMessage);
end;

{*******************************************************************************
* writeBleDeviceInfo
*******************************************************************************}
procedure writeBleDeviceInfo(aLogger: TLogCore; aIndex: Integer;
    const aMac: string; const aIdentifier: string; const aDeviceType: string;
    const aComPort: string; const aConsoleLine: string);
var
    jsonLine: string;
    consoleLine: string;
begin
    if aLogger <> nil then
    begin
        jsonLine := '{' + jsonLogTimestamp('br') +
            ',"event":"ble_device"' +
            ',"source":"ble"' +
            ',"level":"info"' +
            ',"index":' + IntToStr(aIndex) +
            ',"mac":"' + jsonEscape(aMac) + '"' +
            ',"identifier":"' + jsonEscape(aIdentifier) + '"';

        if aDeviceType <> '' then
            jsonLine := jsonLine + ',"device_type":"' + jsonEscape(aDeviceType) + '"';
        if aComPort <> '' then
            jsonLine := jsonLine + ',"com_port":"' + jsonEscape(aComPort) + '"';

        jsonLine := jsonLine + '}';
        aLogger.pushLine(jsonLine);
        aLogger.flush;
    end;
    if aConsoleLine <> '' then
        consoleLine := aConsoleLine
    else
        consoleLine := Format('  [%d] %s [%s]', [aIndex, aIdentifier, aMac]);
    TLogCore.writeConsoleLine(aLogger, consoleLine);
end;

{*******************************************************************************
* writeBleDeviceError
*******************************************************************************}
procedure writeBleDeviceError(aLogger: TLogCore; const aMac: string;
    const aMessage: string; const aConsoleLine: string);
begin
    if aLogger <> nil then
    begin
        aLogger.pushLine('{' + jsonLogTimestamp('br') +
            ',"event":"ble_device"' +
            ',"source":"ble"' +
            ',"level":"error"' +
            ',"mac":"' + jsonEscape(aMac) + '"' +
            ',"message":"' + jsonEscape(aMessage) + '"}');
        aLogger.flush;
    end;
    if aConsoleLine <> '' then
        TLogCore.writeConsoleLine(aLogger, aConsoleLine)
    else
        TLogCore.writeConsoleLine(aLogger, aMessage);
end;

end.