program BodyMonitor;

{$mode objfpc}{$H+}

uses
    SysUtils,
    Classes,
    Windows,
    fpjson,
    jsonparser,
    SimpleCBle,
    BodyMonitorCore in 'core\BodyMonitorCore.pas',
    HeartRateReader in 'core\HeartRateReader.pas',
    DeviceScanner in 'core\DeviceScanner.pas',
    LogCore,
    JsonLogWriter,
    BleHelper,
    BleLogHelper,
        BleComPortFinder,
        JsonLineProtocol,
        BodyMonitorControlProtocol;

procedure printUsage;
begin
    WriteLn('Usage:');
    WriteLn('  BodyMonitor.exe [--eeg[=<port_or_mac_or_name>]] [--ecg[=<device_id>|<device_name>]] [--log <file|->]');
    WriteLn('  BodyMonitor.exe [--breath[=<device_id>|<device_name>|true|false>] [--breath-min-delta=<ms>] [--breath-rr-max=<ms>]] ...');
    WriteLn('  BodyMonitor.exe [--log-format=<plain|jsonl>] ...');
    WriteLn('  BodyMonitor.exe --list-devices');
    WriteLn('  BodyMonitor.exe --ping-device=<mac>');
    WriteLn('  BodyMonitor.exe --diagnose-eeg=<mac>');
    WriteLn('  BodyMonitor.exe --probe-device=<mac>');
    WriteLn;
    WriteLn('Options:');
    WriteLn('  --eeg[=<spec>]      Enable EEG mode');
    WriteLn('                        <spec> can be: COM port (COM4), BLE MAC (e0:7d:ea:e6:50:40),');
    WriteLn('                        or device name substring (MindWave) [default: MindWave]');
    WriteLn('  --ecg[=<filt>]      Enable ECG mode (BLE address or case-insensitive name substring)');
    WriteLn('  --breath[=<x>]      Enable breath phase detection [default: false]');
    WriteLn('                        true: enable breath detection for ECG stream');
    WriteLn('                        false: disable breath detection');
    WriteLn('                        <device>: if --ecg absent, acts as ECG selector and prints only breath info');
    WriteLn('  --breath-min-delta  Minimum local phase delta in ms [default: 3.0]');
    WriteLn('  --breath-rr-max     Maximum valid RR in ms for outlier reject [default: 1300.0]');
    WriteLn('  --eeg-stale-sec     EEG disconnect threshold in seconds [default: 10]');
    WriteLn('  --log <file>        Write parameter log to <file>');
    WriteLn('  --log -             Write parameter log to stdout');
    WriteLn('  --log-format        Log output format: plain or jsonl [default: plain]');
    WriteLn('  --full-scan         Process all scanned devices (default: false for --eeg/--ecg)');
    WriteLn('  --list-devices      List all available COM port devices and exit');
    WriteLn('  --ping-device       Quickly check whether a specific BLE MAC is currently reachable');
    WriteLn('  --diagnose-eeg      Read-only EEG diagnostic: WMI COM lookup + BLE reachability (no TG_Connect)');
    WriteLn('  --probe-device      Probe and classify a specific BLE MAC address');
    WriteLn('  --probe-workers     Max concurrent BLE probe workers for list_devices');
    WriteLn('                        [default: number of discovered devices]');
    WriteLn('  --server            Start persistent Bun-controlled server mode');
    WriteLn('  --keep-alive-sec    Server keep-alive interval in seconds [default: 15]');
    WriteLn('  --init-ble          Initialize BLE stack immediately in --server mode');
    WriteLn;
    WriteLn('Examples:');
    WriteLn('  BodyMonitor.exe --list-devices');
    WriteLn('  BodyMonitor.exe --list-devices --probe-workers=6');
    WriteLn('  BodyMonitor.exe --ping-device=e0:7d:ea:e6:50:40');
    WriteLn('  BodyMonitor.exe --probe-device=e0:7d:ea:e6:50:40');
    WriteLn('  BodyMonitor.exe --eeg');
    WriteLn('  BodyMonitor.exe --eeg=COM40');
    WriteLn('  BodyMonitor.exe --eeg=e0:7d:ea:e6:50:40');
    WriteLn('  BodyMonitor.exe --eeg=MindWave');
    WriteLn('  BodyMonitor.exe --ecg');
    WriteLn('  BodyMonitor.exe --ecg=f3:09:f1:14:8c:99');
    WriteLn('  BodyMonitor.exe --ecg=h9z');
    WriteLn('  BodyMonitor.exe --ecg --full-scan');
    WriteLn('  BodyMonitor.exe --breath');
    WriteLn('  BodyMonitor.exe --breath=f3:09:f1:14:8c:99');
    WriteLn('  BodyMonitor.exe --ecg=h9z --breath=true --breath-min-delta=2.0');
    WriteLn('  BodyMonitor.exe --eeg=MindWave --ecg=h9z --log session.jsonl');
end;

{*******************************************************************************
* isComPortSpec
*******************************************************************************}
function isComPortSpec(const aSpec: string): Boolean;
begin
    Result := LowerCase(Copy(Trim(aSpec), 1, 3)) = 'com';
end;

{*******************************************************************************
* writeEegResolveEvent
*******************************************************************************}
procedure writeEegResolveEvent(aLogger: TLogCore; const aStage: string;
    const aLevel: string; const aMessage: string);
begin
    if aLogger <> nil then
    begin
        aLogger.pushLine('{' + jsonLogTimestamp('br') +
            ',"event":"eeg_scan"' +
            ',"source":"eeg"' +
            ',"level":"' + aLevel + '"' +
            ',"stage":"' + aStage + '"' +
            ',"message":"' + jsonEscape(aMessage) + '"}');
        aLogger.flush;
    end;
    TLogCore.writeConsoleLine(aLogger, aMessage);
end;

{*******************************************************************************
* resolveEegPort
*******************************************************************************}
function resolveEegPort(const aEegSpec: AnsiString; aLogger: TLogCore): AnsiString;
var
    msg: string;
    specText: string;
begin
    specText := Trim(string(aEegSpec));
    if specText = '' then
        specText := 'MindWave';

    if isComPortSpec(specText) then
        Exit(AnsiString(specText));

    if Pos(':', specText) > 0 then
    begin
        msg := Format('EEG: Searching for COM port by BLE MAC %s...', [specText]);
        writeEegResolveEvent(aLogger, 'resolve_mac', 'info', msg);
        Result := AnsiString(TBleComPortFinder.findComPortByBleMacAddress(specText));
    end
    else
    begin
        msg := Format('EEG: Searching for device "%s" by name...', [specText]);
        writeEegResolveEvent(aLogger, 'resolve_name', 'info', msg);
        Result := AnsiString(TBleComPortFinder.findComPortByDeviceName(specText));
    end;

    if string(Result) = '' then
    begin
        if Pos(':', specText) > 0 then
            writeEegResolveEvent(aLogger, 'resolve_failed', 'error',
                'ERROR: Could not find COM port for the given BLE MAC address.')
        else
            writeEegResolveEvent(aLogger, 'resolve_failed', 'error',
                Format('ERROR: Could not find COM port for device "%s".', [specText]));
        Exit('');
    end;

    msg := Format('EEG: Found COM port: %s', [string(Result)]);
    writeEegResolveEvent(aLogger, 'resolve_success', 'info', msg);
end;

{*******************************************************************************
* writeListDeviceLine
*******************************************************************************}
procedure writeListDeviceLine(aLogger: TLogCore; aIndex: Integer;
    const aMac: string; const aIdentifier: string; const aDeviceType: string;
    const aComPort: string; const aConsoleLine: string = '');
begin
    writeBleDeviceInfo(aLogger, aIndex, aMac, aIdentifier, aDeviceType, aComPort,
        aConsoleLine);
end;

function jsonBoolText(aValue: Boolean): string;
begin
    if aValue then
        Result := 'true'
    else
        Result := 'false';
end;

const
    AUTO_LIST_DEVICES_PROBE_WORKER_COUNT = 0;
    LIST_DEVICES_PROBE_TIMEOUT_MS = 35000;
    LIST_DEVICES_WORKER_POLL_MS = 25;

var
    gListDevicesProbeWorkerCount: Integer = AUTO_LIST_DEVICES_PROBE_WORKER_COUNT;

type
    TProbeDeviceResult = record
        Mac                     : string;
        Identifier              : string;
        DeviceType              : string;
        Message                 : string;
        Ok                      : Boolean;
        Connectable             : Boolean;
    end;

    TProbeWorker = record
        DeviceIndex             : Integer;
        Mac                     : string;
        ProcessHandle           : THandle;
        OutputReadHandle        : THandle;
        StartedTick             : QWord;
    end;

    TProbeWorkerArray = array of TProbeWorker;

procedure writeBlePingResult(aLogger: TLogCore; const aMac: string;
    const aIdentifier: string; aOk: Boolean; const aMessage: string);
var
    jsonLine: string;
    consoleLine: string;
    level: string;
begin
    if aOk then
        level := 'info'
    else
        level := 'error';

    if aLogger <> nil then
    begin
        jsonLine := '{' + jsonLogTimestamp('br') +
            ',"event":"ble_ping"' +
            ',"source":"ble"' +
            ',"level":"' + level + '"' +
            ',"ok":' + jsonBoolText(aOk) +
            ',"mac":"' + jsonEscape(aMac) + '"';

        if aIdentifier <> '' then
            jsonLine := jsonLine + ',"identifier":"' + jsonEscape(aIdentifier) + '"';
        if aMessage <> '' then
            jsonLine := jsonLine + ',"message":"' + jsonEscape(aMessage) + '"';

        jsonLine := jsonLine + '}';
        aLogger.pushLine(jsonLine);
        aLogger.flush;
    end;

    if aOk then
    begin
        if aIdentifier <> '' then
            consoleLine := Format('Ping OK: %s [%s]', [aIdentifier, aMac])
        else
            consoleLine := Format('Ping OK: [%s]', [aMac]);
    end
    else if aMessage <> '' then
        consoleLine := aMessage
    else
        consoleLine := Format('Ping failed: [%s]', [aMac]);

    TLogCore.writeConsoleLine(aLogger, consoleLine);
end;

procedure writeBleProbeResult(aLogger: TLogCore; const aMac: string;
    const aIdentifier: string; const aDeviceType: string; aOk: Boolean;
    aConnectable: Boolean; const aMessage: string);
var
    consoleLine: string;
    jsonLine: string;
    level: string;
begin
    if aOk then
        level := 'info'
    else
        level := 'error';

    if aLogger <> nil then
    begin
        jsonLine := '{' + jsonLogTimestamp('br') +
            ',"event":"ble_probe"' +
            ',"source":"ble"' +
            ',"level":"' + level + '"' +
            ',"ok":' + jsonBoolText(aOk) +
            ',"connectable":' + jsonBoolText(aConnectable) +
            ',"mac":"' + jsonEscape(aMac) + '"';

        if aIdentifier <> '' then
            jsonLine := jsonLine + ',"identifier":"' + jsonEscape(aIdentifier) + '"';
        if aDeviceType <> '' then
            jsonLine := jsonLine + ',"device_type":"' + jsonEscape(aDeviceType) + '"';
        if aMessage <> '' then
            jsonLine := jsonLine + ',"message":"' + jsonEscape(aMessage) + '"';

        jsonLine := jsonLine + '}';
        aLogger.pushLine(jsonLine);
        aLogger.flush;
    end;

    if aOk then
    begin
        if aIdentifier <> '' then
            consoleLine := Format('Probe OK: %s [%s] => %s', [aIdentifier, aMac, aDeviceType])
        else
            consoleLine := Format('Probe OK: [%s] => %s', [aMac, aDeviceType]);
    end
    else if aMessage <> '' then
        consoleLine := aMessage
    else if not aConnectable then
        consoleLine := Format('Probe skipped: device [%s] is not connectable.', [aMac])
    else
        consoleLine := Format('Probe failed: [%s]', [aMac]);

    TLogCore.writeConsoleLine(aLogger, consoleLine);
end;

procedure writeBleScanDeviceStatus(aLogger: TLogCore; const aMac: string;
    const aStage: string; aIndex: Integer; aTotalCount: Integer;
    aCompletedCount: Integer; const aMessage: string = '');
var
    consoleLine: string;
    jsonLine: string;
    level: string;
begin
    if (aStage = 'failed') or (aStage = 'cancelled') then
        level := 'error'
    else
        level := 'info';

    if aLogger <> nil then
    begin
        jsonLine := '{' + jsonLogTimestamp('br') +
            ',"event":"ble_scan_device"' +
            ',"source":"ble"' +
            ',"level":"' + level + '"' +
            ',"mac":"' + jsonEscape(aMac) + '"' +
            ',"stage":"' + jsonEscape(aStage) + '"' +
            ',"index":' + IntToStr(aIndex) +
            ',"total":' + IntToStr(aTotalCount) +
            ',"completed":' + IntToStr(aCompletedCount);

        if aMessage <> '' then
            jsonLine := jsonLine + ',"message":"' + jsonEscape(aMessage) + '"';

        jsonLine := jsonLine + '}';
        aLogger.pushLine(jsonLine);
        aLogger.flush;
    end;

    if aStage = 'queued' then
        consoleLine := Format('  [%d/%d] queued probe for [%s]',
            [aIndex, aTotalCount, aMac])
    else if aStage = 'probing' then
        consoleLine := Format('  [%d/%d] probing [%s]...',
            [aIndex, aTotalCount, aMac])
    else if aStage = 'complete' then
        consoleLine := Format('  [%d/%d] probe complete for [%s] (%d/%d done)',
            [aIndex, aTotalCount, aMac, aCompletedCount, aTotalCount])
    else if aStage = 'not_connectable' then
        consoleLine := Format('  [%d/%d] [%s] is not connectable (%d/%d done)',
            [aIndex, aTotalCount, aMac, aCompletedCount, aTotalCount])
    else if aStage = 'failed' then
        consoleLine := Format('  [%d/%d] probe failed for [%s] (%d/%d done)',
            [aIndex, aTotalCount, aMac, aCompletedCount, aTotalCount])
    else if aStage = 'cancelled' then
        consoleLine := Format('  [%d/%d] probe cancelled for [%s]',
            [aIndex, aTotalCount, aMac])
    else
        consoleLine := Format('  [%d/%d] %s [%s]', [aIndex, aTotalCount, aStage, aMac]);

    if aMessage <> '' then
        consoleLine := consoleLine + ' - ' + aMessage;

    TLogCore.writeConsoleLine(aLogger, consoleLine);
end;

function readProbeWorkerOutputText(aReadHandle: THandle): string;
var
    bytesRead: DWORD;
    chunk: RawByteString;
    readOk: BOOL;
    buffer: array[0..4095] of AnsiChar;
begin
    Result := '';
    if aReadHandle = 0 then
        Exit;

    repeat
        readOk := ReadFile(aReadHandle, buffer, SizeOf(buffer), bytesRead, nil);
        if bytesRead > 0 then
        begin
            SetString(chunk, PAnsiChar(@buffer[0]), Integer(bytesRead));
            Result := Result + string(chunk);
        end;

        if readOk and (bytesRead = 0) then
            Break;

        if (not readOk) and (GetLastError() = ERROR_BROKEN_PIPE) then
            Break;

        if not readOk then
            Break;
    until False;
end;

function tryParseBleProbeResultLine(const aLine: string;
    out aResult: TProbeDeviceResult): Boolean;
var
    jsonData: TJSONData;
    jsonObject: TJSONObject;
    eventName: string;
begin
    Result := False;
    aResult.Mac := '';
    aResult.Identifier := '';
    aResult.DeviceType := '';
    aResult.Message := '';
    aResult.Ok := False;
    aResult.Connectable := False;

    if Trim(aLine) = '' then
        Exit;

    jsonData := nil;
    try
        jsonData := GetJSON(aLine);
        if (jsonData = nil) or (jsonData.JSONType <> jtObject) then
            Exit;

        jsonObject := TJSONObject(jsonData);
        eventName := LowerCase(Trim(jsonObject.Get('event', '')));
        if eventName <> 'ble_probe' then
            Exit;

        aResult.Mac := LowerCase(Trim(jsonObject.Get('mac', '')));
        aResult.Identifier := Trim(jsonObject.Get('identifier', ''));
        aResult.DeviceType := Trim(jsonObject.Get('device_type', ''));
        aResult.Message := Trim(jsonObject.Get('message', ''));
        aResult.Ok := jsonObject.Get('ok', False);
        aResult.Connectable := jsonObject.Get('connectable', False);
        Result := aResult.Mac <> '';
    except
        Result := False;
    end;

    if jsonData <> nil then
        jsonData.Free;
end;

function tryParseBleProbeResultText(const aText: string;
    out aResult: TProbeDeviceResult): Boolean;
var
    i: Integer;
    lines: TStringList;
begin
    Result := False;
    lines := TStringList.Create();
    try
        lines.Text := aText;
        for i := lines.Count - 1 downto 0 do
            if tryParseBleProbeResultLine(lines[i], aResult) then
                Exit(True);
    finally
        FreeAndNil(lines);
    end;
end;

procedure releaseProbeWorker(var aWorker: TProbeWorker);
begin
    if aWorker.OutputReadHandle <> 0 then
    begin
        CloseHandle(aWorker.OutputReadHandle);
        aWorker.OutputReadHandle := 0;
    end;

    if aWorker.ProcessHandle <> 0 then
    begin
        CloseHandle(aWorker.ProcessHandle);
        aWorker.ProcessHandle := 0;
    end;

    aWorker.DeviceIndex := -1;
    aWorker.Mac := '';
    aWorker.StartedTick := 0;
end;

function isProbeWorkerRunning(const aWorker: TProbeWorker): Boolean;
begin
    Result := (aWorker.ProcessHandle <> 0) and
        (WaitForSingleObject(aWorker.ProcessHandle, 0) = WAIT_TIMEOUT);
end;

procedure terminateProbeWorker(var aWorker: TProbeWorker);
begin
    if isProbeWorkerRunning(aWorker) then
        TerminateProcess(aWorker.ProcessHandle, 1);
end;

function startProbeWorker(const aMac: string; aDeviceIndex: Integer;
    out aWorker: TProbeWorker): Boolean;
var
    commandLine: string;
    stdoutRead: THandle;
    stdoutWrite: THandle;
    created: BOOL;
    startupInfo: TStartupInfo;
    processInfo: TProcessInformation;
    security: TSecurityAttributes;
begin
    aWorker.DeviceIndex := -1;
    aWorker.Mac := '';
    aWorker.ProcessHandle := 0;
    aWorker.OutputReadHandle := 0;
    aWorker.StartedTick := 0;
    Result := False;

    stdoutRead := 0;
    stdoutWrite := 0;

    FillChar(security, SizeOf(security), 0);
    security.nLength := SizeOf(security);
    security.bInheritHandle := True;

    if not CreatePipe(stdoutRead, stdoutWrite, @security, 0) then
        Exit;

    try
        SetHandleInformation(stdoutRead, HANDLE_FLAG_INHERIT, 0);

        FillChar(startupInfo, SizeOf(startupInfo), 0);
        startupInfo.cb := SizeOf(startupInfo);
        startupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
        startupInfo.wShowWindow := SW_HIDE;
        startupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
        startupInfo.hStdOutput := stdoutWrite;
        startupInfo.hStdError := stdoutWrite;

        FillChar(processInfo, SizeOf(processInfo), 0);
        commandLine := '"' + ParamStr(0) + '"' +
            ' --probe-device=' + LowerCase(Trim(aMac)) +
            ' --log - --log-format=jsonl';

        created := CreateProcess(nil, PChar(commandLine), nil, nil, True,
            CREATE_NO_WINDOW, nil, nil, startupInfo, processInfo);
        if not created then
            Exit;

        CloseHandle(stdoutWrite);
        stdoutWrite := 0;
        CloseHandle(processInfo.hThread);

        aWorker.DeviceIndex := aDeviceIndex;
        aWorker.Mac := LowerCase(Trim(aMac));
        aWorker.ProcessHandle := processInfo.hProcess;
        aWorker.OutputReadHandle := stdoutRead;
        aWorker.StartedTick := GetTickCount64();
        stdoutRead := 0;
        Result := True;
    finally
        if stdoutWrite <> 0 then
            CloseHandle(stdoutWrite);
        if stdoutRead <> 0 then
            CloseHandle(stdoutRead);
    end;
end;

function runListDevicesScan(aLogger: TLogCore; aScanner: TDeviceScanner;
    aRetainPeripheralHandles: Boolean; aCancelFlag: PLongInt;
    out aScanResult: TDeviceScanResult; out aErrorMessage: string): Boolean;
var
    i: Integer;
    activeIndex: Integer;
    totalCount: Integer;
    nextPending: Integer;
    completedCount: Integer;
    effectiveProbeWorkerCount: Integer;
    newWorker: TProbeWorker;
    pendingIndices: array of Integer;
    probeResult: TProbeDeviceResult;
    workerOutput: string;
    activeWorkers: TProbeWorkerArray;

    function isCancelRequested(): Boolean;
    begin
        Result := (aCancelFlag <> nil) and (aCancelFlag^ <> 0);
    end;

    function classificationConsoleLine(const aDevice: TScannedDevice): string;
    var
        suffix: string;
    begin
        suffix := aDevice.DeviceType;
        if aDevice.ComPort <> '' then
            suffix := suffix + ' · ' + aDevice.ComPort;

        Result := Format('      classified: %s [%s] => %s',
            [aDevice.Identifier, aDevice.Mac, suffix]);
    end;

    procedure appendPendingDeviceIndex(aDeviceIndex: Integer);
    var
        nextIndex: Integer;
    begin
        nextIndex := Length(pendingIndices);
        SetLength(pendingIndices, nextIndex + 1);
        pendingIndices[nextIndex] := aDeviceIndex;
    end;

    procedure appendActiveWorker(const aWorker: TProbeWorker);
    var
        nextIndex: Integer;
    begin
        nextIndex := Length(activeWorkers);
        SetLength(activeWorkers, nextIndex + 1);
        activeWorkers[nextIndex] := aWorker;
    end;

    procedure removeActiveWorker(aIndex: Integer);
    var
        j: Integer;
    begin
        releaseProbeWorker(activeWorkers[aIndex]);
        for j := aIndex to Length(activeWorkers) - 2 do
            activeWorkers[j] := activeWorkers[j + 1];
        SetLength(activeWorkers, Length(activeWorkers) - 1);
    end;

    procedure failProbe(const aDeviceIndex: Integer; const aMessage: string);
    begin
        Inc(completedCount);
        writeBleScanDeviceStatus(aLogger,
            aScanResult.Devices[aDeviceIndex].Mac,
            'failed',
            aScanResult.Devices[aDeviceIndex].Index,
            totalCount,
            completedCount,
            aMessage);
    end;

    procedure finalizeProbe(aDeviceIndex: Integer;
        const aParsedResult: TProbeDeviceResult; const aFallbackMessage: string);
    begin
        if aParsedResult.Ok then
        begin
            if aParsedResult.Identifier <> '' then
                aScanResult.Devices[aDeviceIndex].Identifier := aParsedResult.Identifier;
            if aParsedResult.DeviceType <> '' then
            begin
                aScanResult.Devices[aDeviceIndex].DeviceType := aParsedResult.DeviceType;
                aScanResult.Devices[aDeviceIndex].HasHeartRate :=
                    Pos('Heart Rate', aParsedResult.DeviceType) > 0;
            end;

            aScanResult.Devices[aDeviceIndex].Connectable := aParsedResult.Connectable;
            aScanResult.Devices[aDeviceIndex].Connected := True;

            writeListDeviceLine(aLogger,
                aScanResult.Devices[aDeviceIndex].Index,
                aScanResult.Devices[aDeviceIndex].Mac,
                aScanResult.Devices[aDeviceIndex].Identifier,
                aScanResult.Devices[aDeviceIndex].DeviceType,
                aScanResult.Devices[aDeviceIndex].ComPort,
                classificationConsoleLine(aScanResult.Devices[aDeviceIndex]));

            Inc(completedCount);
            writeBleScanDeviceStatus(aLogger,
                aScanResult.Devices[aDeviceIndex].Mac,
                'complete',
                aScanResult.Devices[aDeviceIndex].Index,
                totalCount,
                completedCount,
                aParsedResult.Message);
            Exit;
        end;

        aScanResult.Devices[aDeviceIndex].Connectable := aParsedResult.Connectable;
        aScanResult.Devices[aDeviceIndex].Connected := False;

        if not aParsedResult.Connectable then
        begin
            Inc(completedCount);
            writeBleScanDeviceStatus(aLogger,
                aScanResult.Devices[aDeviceIndex].Mac,
                'not_connectable',
                aScanResult.Devices[aDeviceIndex].Index,
                totalCount,
                completedCount,
                aParsedResult.Message);
            Exit;
        end;

        failProbe(aDeviceIndex, aFallbackMessage);
    end;

begin
    Result := False;
    aErrorMessage := '';
    FillChar(aScanResult, SizeOf(aScanResult), 0);
    SetLength(aScanResult.Devices, 0);

    try
        SetLength(pendingIndices, 0);
        SetLength(activeWorkers, 0);

        if not aScanner.discover(aRetainPeripheralHandles, aScanResult) then
        begin
            aErrorMessage := 'BLE scan failed';
            Exit;
        end;

        totalCount := Length(aScanResult.Devices);
        if gListDevicesProbeWorkerCount > 0 then
            effectiveProbeWorkerCount := gListDevicesProbeWorkerCount
        else
            effectiveProbeWorkerCount := totalCount;

        nextPending := 0;
        completedCount := 0;

        for i := 0 to totalCount - 1 do
        begin
            writeListDeviceLine(aLogger,
                aScanResult.Devices[i].Index,
                aScanResult.Devices[i].Mac,
                aScanResult.Devices[i].Identifier,
                aScanResult.Devices[i].DeviceType,
                aScanResult.Devices[i].ComPort);

            if not aScanResult.Devices[i].Connectable then
            begin
                Inc(completedCount);
                writeBleScanDeviceStatus(aLogger,
                    aScanResult.Devices[i].Mac,
                    'not_connectable',
                    aScanResult.Devices[i].Index,
                    totalCount,
                    completedCount,
                    'Device is not connectable.');
                Continue;
            end;

            appendPendingDeviceIndex(i);
            writeBleScanDeviceStatus(aLogger,
                aScanResult.Devices[i].Mac,
                'queued',
                aScanResult.Devices[i].Index,
                totalCount,
                completedCount,
                'Device queued for probe.');
        end;

        while (nextPending < Length(pendingIndices)) or (Length(activeWorkers) > 0) do
        begin
            if isCancelRequested() then
            begin
                for activeIndex := 0 to Length(activeWorkers) - 1 do
                    terminateProbeWorker(activeWorkers[activeIndex]);

                aErrorMessage := 'Cancelled';
                Exit;
            end;

            while (Length(activeWorkers) < effectiveProbeWorkerCount) and
                (nextPending < Length(pendingIndices)) do
            begin
                i := pendingIndices[nextPending];
                Inc(nextPending);

                if startProbeWorker(aScanResult.Devices[i].Mac, i, newWorker) then
                begin
                    appendActiveWorker(newWorker);
                    writeBleScanDeviceStatus(aLogger,
                        aScanResult.Devices[i].Mac,
                        'probing',
                        aScanResult.Devices[i].Index,
                        totalCount,
                        completedCount,
                        'Device probe started.');
                end
                else
                    failProbe(i, 'Failed to start probe worker.');
            end;

            activeIndex := 0;
            while activeIndex < Length(activeWorkers) do
            begin
                if isProbeWorkerRunning(activeWorkers[activeIndex]) and
                    ((GetTickCount64() - activeWorkers[activeIndex].StartedTick) <
                        LIST_DEVICES_PROBE_TIMEOUT_MS) then
                begin
                    Inc(activeIndex);
                    Continue;
                end;

                terminateProbeWorker(activeWorkers[activeIndex]);

                workerOutput := readProbeWorkerOutputText(activeWorkers[activeIndex].OutputReadHandle);
                if tryParseBleProbeResultText(workerOutput, probeResult) then
                    finalizeProbe(activeWorkers[activeIndex].DeviceIndex,
                        probeResult,
                        'BLE device probe could not classify the device.')
                else
                    failProbe(activeWorkers[activeIndex].DeviceIndex,
                        'Probe worker returned no valid result.');

                removeActiveWorker(activeIndex);
            end;

            if Length(activeWorkers) > 0 then
                Sleep(LIST_DEVICES_WORKER_POLL_MS);
        end;

        writeBleScanLine(aLogger, 'probe_summary', 'info',
            Format('BLE probe phase complete: %d/%d device(s) processed.',
                [completedCount, totalCount]));
        Result := True;
    except
        on E: Exception do
        begin
            aErrorMessage := E.ClassName + ': ' + E.Message;
            Result := False;
        end;
    end;
end;

{*******************************************************************************
* printListDevices
*   Scans BLE devices, classifies them by services and shows COM ports.
*******************************************************************************}
procedure printListDevices(aLogger: TLogCore);
var
    errorText: string;
    scanner: TDeviceScanner;
    scanResult: TDeviceScanResult;
begin
    scanner := TDeviceScanner.Create(aLogger);
    try
        if not runListDevicesScan(aLogger, scanner, False, nil,
            scanResult, errorText) then
            Exit;
    finally
        FreeAndNil(scanner);
    end;
end;

procedure pingDevice(const aMac: string; aLogger: TLogCore;
    out aSuccess: Boolean);
var
    identifier: string;
    scanner: TDeviceScanner;
    targetMac: string;
begin
    targetMac := LowerCase(Trim(aMac));
    aSuccess := False;

    if targetMac = '' then
    begin
        writeBlePingResult(aLogger, '', '', False,
            'ERROR: Empty --ping-device target.');
        Exit;
    end;

    scanner := TDeviceScanner.Create(aLogger);
    try
        aSuccess := scanner.pingAddress(targetMac, identifier);
        if aSuccess then
            writeBlePingResult(aLogger, targetMac, identifier, True,
                'BLE device is reachable.')
        else
            writeBlePingResult(aLogger, targetMac, '', False,
                'BLE device is not reachable.');
    finally
        FreeAndNil(scanner);
    end;
end;

{*******************************************************************************
* writeEegDiagnosticsResult
*******************************************************************************}
procedure writeEegDiagnosticsResult(aLogger: TLogCore; const aMac: string;
    const aOverallKey: string; const aMessage: string;
    aBleOk: Boolean; const aBleIdentifier: string; aBleElapsedMs: Int64;
    const aBleMessage: string;
    aComFound: Boolean; const aComPort: string;
    const aComDescription: string; const aComPnpDeviceId: string);
var
    jsonLine: string;
    level: string;
    updatedAtMs: Int64;
begin
    if aLogger = nil then
        Exit;

    if (aOverallKey = 'ok') or (aOverallKey = 'checking') then
        level := 'info'
    else
        level := 'error';

    updatedAtMs := Int64(GetTickCount64());

    jsonLine := '{' + jsonLogTimestamp('br') +
        ',"event":"eeg_diagnostics"' +
        ',"source":"eeg"' +
        ',"level":"' + level + '"' +
        ',"mac":"' + jsonEscape(aMac) + '"' +
        ',"overall_key":"' + jsonEscape(aOverallKey) + '"' +
        ',"updated_at_ms":' + IntToStr(updatedAtMs) +
        ',"ble":{"ok":' + jsonBoolText(aBleOk);

    if aBleIdentifier <> '' then
        jsonLine := jsonLine + ',"identifier":"' + jsonEscape(aBleIdentifier) + '"';
    if aBleElapsedMs >= 0 then
        jsonLine := jsonLine + ',"elapsed_ms":' + IntToStr(aBleElapsedMs);
    if aBleMessage <> '' then
        jsonLine := jsonLine + ',"message":"' + jsonEscape(aBleMessage) + '"';

    jsonLine := jsonLine + '}' +
        ',"com":{"found":' + jsonBoolText(aComFound);

    if aComPort <> '' then
        jsonLine := jsonLine + ',"port":"' + jsonEscape(aComPort) + '"';
    if aComDescription <> '' then
        jsonLine := jsonLine + ',"description":"' + jsonEscape(aComDescription) + '"';
    if aComPnpDeviceId <> '' then
        jsonLine := jsonLine + ',"pnp_device_id":"' + jsonEscape(aComPnpDeviceId) + '"';

    jsonLine := jsonLine + '}';

    if aMessage <> '' then
        jsonLine := jsonLine + ',"message":"' + jsonEscape(aMessage) + '"';

    jsonLine := jsonLine + '}';

    aLogger.pushLine(jsonLine);
    aLogger.flush;
end;

{*******************************************************************************
* diagnoseEeg
*   Read-only EEG diagnostic: WMI COM lookup + lightweight BLE reachability.
*   Does NOT call TG_Connect or open the COM port.
*******************************************************************************}
procedure diagnoseEeg(const aMac: string; aLogger: TLogCore;
    out aSuccess: Boolean);
var
    targetMac: string;
    scanner: TDeviceScanner;
    bleOk: Boolean;
    bleIdentifier: string;
    bleStartMs: Int64;
    bleElapsedMs: Int64;
    bleMessage: string;
    serialDevice: TSerialDeviceInfo;
    comFound: Boolean;
    overallKey: string;
    diagMessage: string;
begin
    targetMac := LowerCase(Trim(aMac));
    aSuccess := False;

    if targetMac = '' then
    begin
        TLogCore.writeErrorLine(aLogger, 'ERROR: Empty --diagnose-eeg target.');
        Exit;
    end;

    { WMI COM port lookup - read-only, no port opening }
    FillChar(serialDevice, SizeOf(serialDevice), 0);
    comFound := TBleComPortFinder.findSerialDeviceByBleMacAddress(targetMac, serialDevice);

    { Lightweight BLE reachability check }
    bleOk := False;
    bleIdentifier := '';
    bleMessage := '';
    bleElapsedMs := -1;

    scanner := TDeviceScanner.Create(aLogger);
    try
        bleStartMs := Int64(GetTickCount64());
        bleOk := scanner.pingAddress(targetMac, bleIdentifier);
        bleElapsedMs := Int64(GetTickCount64()) - bleStartMs;
        if bleOk then
            bleMessage := 'BLE device is reachable.'
        else
            bleMessage := 'BLE device is not reachable.';
    finally
        FreeAndNil(scanner);
    end;

    { Determine overall status key }
    if not bleOk then
        overallKey := 'ble_missing'
    else if not comFound then
        overallKey := 'com_missing'
    else
        overallKey := 'ok';

    if comFound then
        diagMessage := Format('COM %s found via WMI for %s.', [serialDevice.DeviceID, targetMac])
    else if bleOk then
        diagMessage := Format('BLE visible but no COM port found in WMI for %s.', [targetMac])
    else
        diagMessage := Format('BLE device %s is not reachable.', [targetMac]);

    writeEegDiagnosticsResult(aLogger, targetMac, overallKey, diagMessage,
        bleOk, bleIdentifier, bleElapsedMs, bleMessage,
        comFound,
        serialDevice.DeviceID,
        serialDevice.Description,
        serialDevice.PNPDeviceID);

    TLogCore.writeConsoleLine(aLogger, diagMessage);
    aSuccess := overallKey = 'ok';
end;

procedure probeDevice(const aMac: string; aLogger: TLogCore;
    out aSuccess: Boolean);
var
    i: Integer;
    scanner: TDeviceScanner;
    targetMac: string;
    filters: TScanFilterArray;
    scanResult: TDeviceScanResult;
begin
    targetMac := LowerCase(Trim(aMac));
    aSuccess := False;

    if targetMac = '' then
    begin
        writeBleProbeResult(aLogger, '', '', '', False, False,
            'ERROR: Empty --probe-device target.');
        Exit;
    end;

    scanner := TDeviceScanner.Create(aLogger);
    try
        SetLength(filters, 1);
        filters[0].Kind := sfAddress;
        filters[0].Value := targetMac;

        if not scanner.scan(filters, False, False, False, scanResult) then
        begin
            writeBleProbeResult(aLogger, targetMac, '', '', False, True,
                'BLE device probe failed.');
            Exit;
        end;

        for i := 0 to Length(scanResult.Devices) - 1 do
        begin
            if LowerCase(Trim(scanResult.Devices[i].Mac)) <> targetMac then
                Continue;

            if not scanResult.Devices[i].Connectable then
            begin
                writeBleProbeResult(aLogger,
                    targetMac,
                    scanResult.Devices[i].Identifier,
                    scanResult.Devices[i].DeviceType,
                    False,
                    False,
                    'BLE device is not connectable.');
                Exit;
            end;

            if not scanResult.Devices[i].Connected then
            begin
                writeBleProbeResult(aLogger,
                    targetMac,
                    scanResult.Devices[i].Identifier,
                    scanResult.Devices[i].DeviceType,
                    False,
                    True,
                    'BLE device probe could not classify the device.');
                Exit;
            end;

            aSuccess := True;
            writeBleProbeResult(aLogger,
                targetMac,
                scanResult.Devices[i].Identifier,
                scanResult.Devices[i].DeviceType,
                True,
                True,
                'BLE device probe completed.');
            Exit;
        end;

        writeBleProbeResult(aLogger, targetMac, '', '', False, True,
            'BLE device was not found during probe.');
    finally
        FreeAndNil(scanner);
    end;
end;

{*******************************************************************************
* preScanEcg
*   Runs a BLE prescan in the main thread and passes the found peripheral
*   to the HeartRateReader, so the ECG thread can skip its own BLE scan.
*******************************************************************************}
procedure preScanEcg(aEcgApp: THeartRateReader; const aEcgFilter: string;
    aFullScan: Boolean; aLogger: TLogCore);
var
    msg: string;
    filters: TScanFilterArray;
    scanner: TDeviceScanner;
    filterText: string;
    scanResult: TDeviceScanResult;
    isAddressFilter: Boolean;
begin
    filterText := Trim(aEcgFilter);
    isAddressFilter := Pos(':', filterText) > 0;

    SetLength(filters, 1);
    filters[0].Kind := sfHeartRateService;
    filters[0].Value := '';

    if filterText <> '' then
    begin
        if isAddressFilter then
        begin
            writeBleScanLine(aLogger, 'filter', 'info',
                Format('ECG address filter active: exact match "%s".', [filterText]));
            SetLength(filters, 2);
            filters[1].Kind := sfAddress;
            filters[1].Value := filterText;
        end
        else
        begin
            writeBleScanLine(aLogger, 'filter', 'info',
                Format('ECG name filter active: contains "%s" (case-insensitive).', [filterText]));
            SetLength(filters, 2);
            filters[1].Kind := sfName;
            filters[1].Value := filterText;
        end;
    end;

    scanner := TDeviceScanner.Create(aLogger);
    try
        if not scanner.scan(filters, aFullScan, True, False, scanResult) then
        begin
            aEcgApp.setPreScannedPeripheral(0, False, False);
            Exit;
        end;

        if scanResult.FirstMatchedPeripheral = 0 then
        begin
            writeBleScanLine(aLogger, 'scan_results', 'error',
                'ERROR: No Heart Rate device found.');
            aEcgApp.setPreScannedPeripheral(0, False, False);
            Exit;
        end;

        msg := Format('Found Heart Rate device: %s [%s]', [
            scanResult.FirstMatchedIdentifier,
            scanResult.FirstMatchedMac]);
        writeBleScanLine(aLogger, 'device_found', 'info', msg);

        aEcgApp.setPreScannedPeripheral(
            scanResult.FirstMatchedPeripheral,
            scanResult.BleLibraryLoaded,
            True);
    finally
        FreeAndNil(scanner);
    end;
end;

type
    TUnknownModeArgProc = procedure(const aArg: string);

    {***************************************************************************
     * TReaderThread
     ***************************************************************************}
    TReaderThread = class(TThread)
private
    Fapp                    : TObject;
    FexitCode               : Integer;
    FerrMessage             : string;

protected
    procedure   executeApp(); virtual; abstract;
    procedure   Execute(); override;

public
    constructor Create(aApp: TObject);

    property ExitCode: Integer read FexitCode;
    property ErrorMessage: string read FerrMessage;
    end;

    {***************************************************************************
     * TEegReaderThread
     ***************************************************************************}
    TEegReaderThread = class(TReaderThread)
private
    FeegPort                : AnsiString;

protected
    procedure   executeApp(); override;

public
    constructor Create(aApp: TBodyMonitorCore; const aEegPort: AnsiString);
    end;

    {***************************************************************************
     * TEcgReaderThread
     ***************************************************************************}
    TEcgReaderThread = class(TReaderThread)
private
    FdeviceFilter           : string;

protected
    procedure   executeApp(); override;

public
    constructor Create(aApp: THeartRateReader; const aDeviceFilter: string);
    end;

    {***************************************************************************
     * TListDevicesThread
     *   Runs BLE list_devices scan in background to keep server loop responsive.
     ***************************************************************************}
    TListDevicesThread = class(TThread)
private
    Flogger                 : TLogCore;
    Fscanner                : TDeviceScanner;
    Fsuccess                : Boolean;
    FcancelRequested        : LongInt;
    FerrMessage             : string;
    FscanResult             : TDeviceScanResult;

protected
    procedure   Execute(); override;

public
    constructor Create();
    destructor  Destroy(); override;
    procedure   requestCancel();
    procedure   emitDeviceLines();
    procedure   cleanupRetainedHandles();

    property Success: Boolean read Fsuccess;
    property ErrorMessage: string read FerrMessage;
    property ScanResult: TDeviceScanResult read FscanResult;
    end;

    {***************************************************************************
     * TStdioCommandLoop
     *   Manages EEG/ECG worker threads via JSONL commands read from stdin.
     *   Activated when BodyMonitor.exe is started with --stdio.
     ***************************************************************************}
    TStdioCommandLoop = class
protected
    Fparams                 : TStringArray;
    Flogger                 : TLogCore;
    FeegApp                 : TBodyMonitorCore;
    FecgApp                 : THeartRateReader;
    FeegThread              : TEegReaderThread;
    FecgThread              : TEcgReaderThread;
    FisRunning              : Boolean;

protected
    function    parseModeArgsFromList(out aUseEeg: Boolean;
        out aEegPort: AnsiString; out aUseEcg: Boolean;
        out aEcgFilter: string; out aLogTarget: string;
        out aLogFormat: TLogOutputFormat;
        out aBreathEnabled: Boolean; out aBreathOnlyOutput: Boolean;
        out aBreathMinDelta: Double; out aBreathMaxRr: Double;
        out aEegStaleSec: Integer;
        out aFullScan: Boolean): Boolean;
    procedure   applySetParam(const aKey: string; const aValue: string);
    function    applyRuntimeParam(const aKey: string;
        const aValue: string; out aErrorText: string): Boolean;
    procedure   prepareEcgApp(aEcgApp: THeartRateReader;
        const aEcgFilter: string; aFullScan: Boolean); virtual;
    procedure   startWorkers();
    procedure   stopWorkers();
    procedure   writeParamUpdatedEvent(const aKey: string;
        const aValue: string);

public
    constructor Create();
    destructor  Destroy(); override;
    procedure   run();
    end;

    {***************************************************************************
     * TServerCommandLoop
     *   Persistent command loop for --server mode with keep-alive checks
     *   and cached BLE device handles from list_devices.
     ***************************************************************************}
    TServerCommandLoop = class(TStdioCommandLoop)
private
    FinitBle                : Boolean;
    FcacheBleLoaded         : Boolean;
    FkeepAliveSec           : Integer;
    FlastPingTick           : QWord;
    FcachedDevices          : TScannedDeviceArray;
    FlistDevicesThread      : TListDevicesThread;
    FlistDevicesCanceled    : Boolean;

private
    procedure   cancelListDevicesScan(const aReason: string = '');
    procedure   clearCachedDevices(aUnloadBle: Boolean = True);
    procedure   releaseListDevicesThread();
    procedure   finishListDevicesFailure(const aErrorText: string);
    procedure   handleListDevices();
    procedure   pollListDevicesThread();
    procedure   warmupBleStack();
    function    takeCachedPeripheral(const aMac: string;
        out aPeripheral: TSimpleBlePeripheral;
        out aIdentifier: string): Boolean;

protected
    procedure   prepareEcgApp(aEcgApp: THeartRateReader;
        const aEcgFilter: string; aFullScan: Boolean); override;

public
    constructor Create(aKeepAliveSec: Integer; aInitBle: Boolean);
    destructor  Destroy(); override;
    procedure   run();
    end;

var
    gConsoleCtrlStopIssued    : LongInt = 0;
    gConsoleEegApp            : TBodyMonitorCore = nil;
    gConsoleEcgApp            : THeartRateReader = nil;
    gConsoleHandlerInstalled  : Boolean = False;

function bodyMonitorConsoleCtrlHandler(aCtrlType: DWORD): BOOL; stdcall;
begin
    case aCtrlType of
        CTRL_C_EVENT,
        CTRL_BREAK_EVENT,
        CTRL_CLOSE_EVENT,
        CTRL_SHUTDOWN_EVENT:
        begin
            if InterlockedExchange(gConsoleCtrlStopIssued, 1) = 0 then
            begin
                if gConsoleEegApp <> nil then
                    gConsoleEegApp.stop();
                if gConsoleEcgApp <> nil then
                    gConsoleEcgApp.stop();
            end
            else
                ExitProcess(130);

            Result := True;
            Exit;
        end;
    end;

    Result := False;
end;

procedure registerConsoleStopTargets(aEegApp: TBodyMonitorCore;
    aEcgApp: THeartRateReader);
begin
    gConsoleEegApp := aEegApp;
    gConsoleEcgApp := aEcgApp;
    InterlockedExchange(gConsoleCtrlStopIssued, 0);

    if not gConsoleHandlerInstalled then
    begin
        SetConsoleCtrlHandler(@bodyMonitorConsoleCtrlHandler, True);
        gConsoleHandlerInstalled := True;
    end;
end;

procedure unregisterConsoleStopTargets();
begin
    gConsoleEegApp := nil;
    gConsoleEcgApp := nil;
    InterlockedExchange(gConsoleCtrlStopIssued, 0);

    if gConsoleHandlerInstalled then
    begin
        SetConsoleCtrlHandler(@bodyMonitorConsoleCtrlHandler, False);
        gConsoleHandlerInstalled := False;
    end;
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor TReaderThread.Create(aApp: TObject);
begin
    inherited Create(True);
    FreeOnTerminate := False;
    Fapp := aApp;
    FexitCode := 0;
    FerrMessage := '';
end;

{*******************************************************************************
* Execute
*******************************************************************************}
procedure TReaderThread.Execute();
begin
    try
        executeApp();
    except
        on E: Exception do
        begin
            FexitCode := 255;
            FerrMessage := E.ClassName + ': ' + E.Message;
        end;
    end;
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor TEegReaderThread.Create(aApp: TBodyMonitorCore; const aEegPort: AnsiString);
begin
    inherited Create(aApp);
    FeegPort := aEegPort;
end;

{*******************************************************************************
* executeApp
*******************************************************************************}
procedure TEegReaderThread.executeApp();
begin
    FexitCode := TBodyMonitorCore(Fapp).run(FeegPort);
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor TEcgReaderThread.Create(aApp: THeartRateReader; const aDeviceFilter: string);
begin
    inherited Create(aApp);
    FdeviceFilter := aDeviceFilter;
end;

{*******************************************************************************
* executeApp
*******************************************************************************}
procedure TEcgReaderThread.executeApp();
begin
    FexitCode := THeartRateReader(Fapp).run(FdeviceFilter);
end;

{*******************************************************************************
* TListDevicesThread.Create
*******************************************************************************}
constructor TListDevicesThread.Create();
begin
    inherited Create(True);
    FreeOnTerminate := False;
    Flogger := TLogCore.Create('-', LOG_FORMAT_JSONL);
    Fscanner := TDeviceScanner.Create(Flogger);
    Fsuccess := False;
    FcancelRequested := 0;
    FerrMessage := '';
    FillChar(FscanResult, SizeOf(FscanResult), 0);
    SetLength(FscanResult.Devices, 0);

    Fscanner.setCancelFlag(@FcancelRequested);
end;

{*******************************************************************************
* TListDevicesThread.Destroy
*******************************************************************************}
destructor TListDevicesThread.Destroy();
begin
    FreeAndNil(Fscanner);
    if Flogger <> nil then
    begin
        Flogger.finish;
        FreeAndNil(Flogger);
    end;
    inherited Destroy;
end;

{*******************************************************************************
* TListDevicesThread.requestCancel
*******************************************************************************}
procedure TListDevicesThread.requestCancel();
begin
    InterlockedExchange(FcancelRequested, 1);
    if Fscanner <> nil then
        Fscanner.requestCancel();
end;

{*******************************************************************************
* TListDevicesThread.Execute
*******************************************************************************}
procedure TListDevicesThread.Execute();
begin
    Fsuccess := runListDevicesScan(Flogger, Fscanner, True,
        @FcancelRequested, FscanResult, FerrMessage);
end;

{*******************************************************************************
* TListDevicesThread.emitDeviceLines
*******************************************************************************}
procedure TListDevicesThread.emitDeviceLines();
var
    i: Integer;
begin
    for i := 0 to Length(FscanResult.Devices) - 1 do
    begin
        writeListDeviceLine(Flogger,
            FscanResult.Devices[i].Index,
            FscanResult.Devices[i].Mac,
            FscanResult.Devices[i].Identifier,
            FscanResult.Devices[i].DeviceType,
            FscanResult.Devices[i].ComPort);
    end;
end;

{*******************************************************************************
* resetScannedDeviceHandle
*******************************************************************************}
procedure resetScannedDeviceHandle(var aDevice: TScannedDevice);
begin
    aDevice.Peripheral := 0;
    aDevice.Connected := False;
end;

{*******************************************************************************
* releaseScannedDeviceHandle
*******************************************************************************}
procedure releaseScannedDeviceHandle(var aDevice: TScannedDevice);
begin
    if aDevice.Connected and (aDevice.Peripheral <> 0) then
        SimpleBlePeripheralDisconnect(aDevice.Peripheral);

    if aDevice.Peripheral <> 0 then
        SimpleBlePeripheralReleaseHandle(aDevice.Peripheral);

    resetScannedDeviceHandle(aDevice);
end;

{*******************************************************************************
* releaseScannedDeviceArray
*******************************************************************************}
procedure releaseScannedDeviceArray(var aDevices: TScannedDeviceArray);
var
    i: Integer;
begin
    for i := 0 to Length(aDevices) - 1 do
        releaseScannedDeviceHandle(aDevices[i]);

    SetLength(aDevices, 0);
end;

{*******************************************************************************
* TListDevicesThread.cleanupRetainedHandles
*******************************************************************************}
procedure TListDevicesThread.cleanupRetainedHandles();
begin
    releaseScannedDeviceArray(FscanResult.Devices);

    if FscanResult.BleLibraryLoaded then
    begin
        SimpleBleUnloadLibrary();
        FscanResult.BleLibraryLoaded := False;
    end;

    FscanResult.FirstMatchedPeripheral := 0;
    FscanResult.FirstMatchedMac := '';
    FscanResult.FirstMatchedIdentifier := '';
end;

{*******************************************************************************
* initModeArgsDefaults
*******************************************************************************}
procedure initModeArgsDefaults(out aUseEeg: Boolean; out aEegPort: AnsiString;
    out aUseEcg: Boolean; out aEcgFilter: string;
    out aLogTarget: string; out aLogFormat: TLogOutputFormat;
    out aBreathEnabled: Boolean;
    out aBreathOnlyOutput: Boolean; out aBreathMinDelta: Double;
    out aBreathMaxRr: Double; out aEegStaleSec: Integer;
    out aFullScan: Boolean);
begin
    aUseEeg := False;
    aUseEcg := False;
    aEcgFilter := '';
    aEegPort := '';
    aLogTarget := '';
    aLogFormat := LOG_FORMAT_PLAIN;
    aBreathEnabled := False;
    aBreathOnlyOutput := False;
    aBreathMinDelta := 3.0;
    aBreathMaxRr := 1300.0;
    aEegStaleSec := 10;
    aFullScan := False;
end;

{*******************************************************************************
* tryParseFloatOptionValue
*******************************************************************************}
function tryParseFloatOptionValue(const aValueText: string;
    aMinValue: Double; out aParsedNumber: Double): Boolean;
var
    f: TFormatSettings;
    normalized: string;
begin
    f := DefaultFormatSettings;
    normalized := StringReplace(aValueText, '.', f.DecimalSeparator,
        [rfReplaceAll]);
    normalized := StringReplace(normalized, ',', f.DecimalSeparator,
        [rfReplaceAll]);
    Result := TryStrToFloat(normalized, aParsedNumber, f) and
        (aParsedNumber > aMinValue);
end;

{*******************************************************************************
* tryParsePositiveIntegerOptionValue
*******************************************************************************}
function tryParsePositiveIntegerOptionValue(const aValueText: string;
    aMinValue: Integer; out aParsedNumber: Integer): Boolean;
begin
    Result := TryStrToInt(Trim(aValueText), aParsedNumber) and
        (aParsedNumber >= aMinValue);
end;

{*******************************************************************************
* parseModeArgsCore
*******************************************************************************}
function parseModeArgsCore(const aArgs: TStringArray;
    aStrictUnknown: Boolean; aOnUnknownArg: TUnknownModeArgProc;
    out aUseEeg: Boolean; out aEegPort: AnsiString;
    out aUseEcg: Boolean; out aEcgFilter: string;
    out aLogTarget: string; out aLogFormat: TLogOutputFormat;
    out aBreathEnabled: Boolean;
    out aBreathOnlyOutput: Boolean; out aBreathMinDelta: Double;
    out aBreathMaxRr: Double; out aEegStaleSec: Integer;
    out aFullScan: Boolean;
    out aErrorMessage: string): Boolean;
var
    n: Integer;
    i: Integer;
    intValue: Integer;
    arg: string;
    eqPos: Integer;
    valueText: string;
    lowerArg: string;
    breathFilter: string;
    parsedNumber: Double;
    isBoolText: Boolean;
    breathSpecified: Boolean;
    logFormatSpecified: Boolean;
begin
    Result := False;
    aErrorMessage := '';
    initModeArgsDefaults(aUseEeg, aEegPort, aUseEcg, aEcgFilter, aLogTarget,
        aLogFormat, aBreathEnabled, aBreathOnlyOutput,
        aBreathMinDelta, aBreathMaxRr, aEegStaleSec, aFullScan);

    n := Length(aArgs);
    breathFilter := '';
    breathSpecified := False;
    logFormatSpecified := False;

    i := 0;
    while i < n do
    begin
        arg := aArgs[i];
        lowerArg := LowerCase(arg);

        if lowerArg = '--log' then
        begin
            if i + 1 >= n then
            begin
                aErrorMessage := '--log requires an argument (filename or -).';
                Exit;
            end;

            aLogTarget := aArgs[i + 1];
            Inc(i, 2);
            Continue;
        end;

        if lowerArg = '--log-format' then
        begin
            Inc(i, 2);
            if i - 1 >= n then
            begin
                aErrorMessage := '--log-format requires one of: plain, jsonl.';
                Exit;
            end;

            valueText := aArgs[i - 1];
            if not TLogCore.tryParseLogFormat(valueText, aLogFormat) then
            begin
                aErrorMessage := 'Invalid --log-format value: ' + valueText +
                    ' (expected plain or jsonl).';
                Exit;
            end;

            logFormatSpecified := True;
            Continue;
        end;

        if lowerArg = '--breath-min-delta' then
        begin
            Inc(i);
            if i >= n then
            begin
                aErrorMessage := '--breath-min-delta requires a numeric value in ms.';
                Exit;
            end;

            valueText := Trim(aArgs[i]);
            if not tryParseFloatOptionValue(valueText, 0.0, parsedNumber) then
            begin
                aErrorMessage := 'Invalid --breath-min-delta value "' +
                    valueText + '" (expected number > 0).';
                Exit;
            end;

            aBreathMinDelta := parsedNumber;
            Inc(i);
            Continue;
        end;

        if Pos('--breath-min-delta=', lowerArg) = 1 then
        begin
            eqPos := Pos('=', arg);
            valueText := Trim(Copy(arg, eqPos + 1, MaxInt));
            if not tryParseFloatOptionValue(valueText, 0.0, parsedNumber) then
            begin
                aErrorMessage := 'Invalid --breath-min-delta value "' +
                    valueText + '" (expected number > 0).';
                Exit;
            end;

            aBreathMinDelta := parsedNumber;
            Inc(i);
            Continue;
        end;

        if lowerArg = '--breath-rr-max' then
        begin
            Inc(i);
            if i >= n then
            begin
                aErrorMessage := '--breath-rr-max requires a numeric value in ms.';
                Exit;
            end;

            valueText := Trim(aArgs[i]);
            if not tryParseFloatOptionValue(valueText, 300.0, parsedNumber) then
            begin
                aErrorMessage := 'Invalid --breath-rr-max value "' +
                    valueText + '" (expected number > 300).';
                Exit;
            end;

            aBreathMaxRr := parsedNumber;
            Inc(i);
            Continue;
        end;

        if lowerArg = '--eeg-stale-sec' then
        begin
            Inc(i);
            if i >= n then
            begin
                aErrorMessage := '--eeg-stale-sec requires an integer value in seconds.';
                Exit;
            end;

            valueText := Trim(aArgs[i]);
            if not tryParsePositiveIntegerOptionValue(valueText, 1, intValue) then
            begin
                aErrorMessage := 'Invalid --eeg-stale-sec value "' +
                    valueText + '" (expected integer >= 1).';
                Exit;
            end;

            aEegStaleSec := intValue;
            Inc(i);
            Continue;
        end;

        if Pos('--eeg-stale-sec=', lowerArg) = 1 then
        begin
            eqPos := Pos('=', arg);
            valueText := Trim(Copy(arg, eqPos + 1, MaxInt));
            if not tryParsePositiveIntegerOptionValue(valueText, 1, intValue) then
            begin
                aErrorMessage := 'Invalid --eeg-stale-sec value "' +
                    valueText + '" (expected integer >= 1).';
                Exit;
            end;

            aEegStaleSec := intValue;
            Inc(i);
            Continue;
        end;

        if Pos('--breath-rr-max=', lowerArg) = 1 then
        begin
            eqPos := Pos('=', arg);
            valueText := Trim(Copy(arg, eqPos + 1, MaxInt));
            if not tryParseFloatOptionValue(valueText, 300.0, parsedNumber) then
            begin
                aErrorMessage := 'Invalid --breath-rr-max value "' +
                    valueText + '" (expected number > 300).';
                Exit;
            end;

            aBreathMaxRr := parsedNumber;
            Inc(i);
            Continue;
        end;

        if Pos('--log-format=', lowerArg) = 1 then
        begin
            eqPos := Pos('=', arg);
            valueText := Trim(Copy(arg, eqPos + 1, MaxInt));
            if valueText = '' then
            begin
                aErrorMessage := '--log-format requires one of: plain, jsonl.';
                Exit;
            end;

            if not TLogCore.tryParseLogFormat(valueText, aLogFormat) then
            begin
                aErrorMessage := 'Invalid --log-format value: ' + valueText +
                    ' (expected plain or jsonl).';
                Exit;
            end;

            logFormatSpecified := True;
            Inc(i);
            Continue;
        end;

        if lowerArg = '--csv-columns' then
        begin
            aErrorMessage := '--csv-columns is no longer supported.';
            Exit;
        end;

        if Pos('--csv-columns=', lowerArg) = 1 then
        begin
            aErrorMessage := '--csv-columns is no longer supported.';
            Exit;
        end;

        if lowerArg = '--full-scan' then
        begin
            if (i + 1 < n) and ((LowerCase(aArgs[i + 1]) = 'true') or
                (LowerCase(aArgs[i + 1]) = 'false')) then
            begin
                aFullScan := LowerCase(aArgs[i + 1]) = 'true';
                Inc(i, 2);
            end
            else
            begin
                aFullScan := True;
                Inc(i);
            end;
            Continue;
        end;

        if Pos('--full-scan=', lowerArg) = 1 then
        begin
            eqPos := Pos('=', arg);
            valueText := LowerCase(Trim(Copy(arg, eqPos + 1, MaxInt)));
            if (valueText <> 'true') and (valueText <> 'false') then
            begin
                aErrorMessage := 'Invalid --full-scan value "' +
                    valueText + '" (expected true or false).';
                Exit;
            end;

            aFullScan := valueText = 'true';
            Inc(i);
            Continue;
        end;

        if lowerArg = '--eeg' then
        begin
            aUseEeg := True;
            Inc(i);
            Continue;
        end;

        if Pos('--eeg=', lowerArg) = 1 then
        begin
            aUseEeg := True;
            eqPos := Pos('=', arg);
            valueText := Trim(Copy(arg, eqPos + 1, MaxInt));
            aEegPort := AnsiString(valueText);
            Inc(i);
            Continue;
        end;

        if lowerArg = '--ecg' then
        begin
            aUseEcg := True;
            aEcgFilter := '';
            Inc(i);
            Continue;
        end;

        if Pos('--ecg=', lowerArg) = 1 then
        begin
            aUseEcg := True;
            eqPos := Pos('=', arg);
            aEcgFilter := Trim(Copy(arg, eqPos + 1, MaxInt));
            Inc(i);
            Continue;
        end;

        if lowerArg = '--breath' then
        begin
            breathSpecified := True;
            aBreathEnabled := True;
            Inc(i);
            Continue;
        end;

        if Pos('--breath=', lowerArg) = 1 then
        begin
            breathSpecified := True;
            eqPos := Pos('=', arg);
            valueText := Trim(Copy(arg, eqPos + 1, MaxInt));
            if valueText = '' then
            begin
                aBreathEnabled := True;
                Inc(i);
                Continue;
            end;

            lowerArg := LowerCase(valueText);
            isBoolText := (lowerArg = 'true') or (lowerArg = 'false');
            if isBoolText then
            begin
                aBreathEnabled := lowerArg = 'true';
                Inc(i);
                Continue;
            end;

            aBreathEnabled := True;
            breathFilter := valueText;
            Inc(i);
            Continue;
        end;

        if lowerArg = '--probe-workers' then
        begin
            Inc(i);
            if i >= n then
            begin
                aErrorMessage := '--probe-workers requires an integer value.';
                Exit;
            end;

            valueText := Trim(aArgs[i]);
            if not tryParsePositiveIntegerOptionValue(valueText, 1, intValue) then
            begin
                aErrorMessage := 'Invalid --probe-workers value "' +
                    valueText + '" (expected integer >= 1).';
                Exit;
            end;

            gListDevicesProbeWorkerCount := intValue;
            Inc(i);
            Continue;
        end;

        if Pos('--probe-workers=', lowerArg) = 1 then
        begin
            eqPos := Pos('=', arg);
            valueText := Trim(Copy(arg, eqPos + 1, MaxInt));
            if not tryParsePositiveIntegerOptionValue(valueText, 1, intValue) then
            begin
                aErrorMessage := 'Invalid --probe-workers value "' +
                    valueText + '" (expected integer >= 1).';
                Exit;
            end;

            gListDevicesProbeWorkerCount := intValue;
            Inc(i);
            Continue;
        end;

        if aStrictUnknown then
        begin
            aErrorMessage := 'Unknown argument "' + arg + '".';
            Exit;
        end;

        if Assigned(aOnUnknownArg) then
            aOnUnknownArg(arg);
        Inc(i);
    end;

    if aBreathMaxRr <= 300.0 then
    begin
        aErrorMessage := '--breath-rr-max must be > 300 ms.';
        Exit;
    end;

    if aBreathEnabled and (aBreathMinDelta <= 0.0) then
    begin
        aErrorMessage := '--breath-min-delta must be > 0 ms.';
        Exit;
    end;

    if breathSpecified and (not aUseEcg) and aBreathEnabled then
    begin
        aUseEcg := True;
        if breathFilter <> '' then
            aEcgFilter := breathFilter;
        aBreathOnlyOutput := True;
    end;

    if aUseEcg and (not breathSpecified) then
        aBreathEnabled := False;

    if aUseEcg and breathSpecified and (not aBreathEnabled) then
        aBreathOnlyOutput := False;

    if not aUseEeg and not aUseEcg then
    begin
        aErrorMessage :=
            'Specify at least one mode: --eeg, --ecg and/or --breath.';
        Exit;
    end;

    if logFormatSpecified and (aLogTarget = '') then
        aLogTarget := '-';

    Result := True;
end;

{*******************************************************************************
* reportUnknownStdioArg
*******************************************************************************}
procedure reportUnknownStdioArg(const aArg: string);
begin
    writeStdoutLine('{"event":"stdio_parse_warn","message":"Unknown argument ' +
        jsonEscape(aArg) + ' skipped"}');
end;

{*******************************************************************************
* parseModeArgs
*******************************************************************************}
function parseModeArgs(out aUseEeg: Boolean; out aEegPort: AnsiString;
    out aUseEcg: Boolean; out aEcgFilter: string;
    out aLogTarget: string; out aLogFormat: TLogOutputFormat;
    out aBreathEnabled: Boolean;
    out aBreathOnlyOutput: Boolean; out aBreathMinDelta: Double;
    out aBreathMaxRr: Double; out aEegStaleSec: Integer;
    out aFullScan: Boolean): Boolean;
var
    n: Integer;
    i: Integer;
    args: TStringArray;
    parseError: string;
begin
    n := ParamCount();
    SetLength(args, n);
    for i := 1 to n do
        args[i - 1] := ParamStr(i);

    Result := parseModeArgsCore(args, True, nil,
        aUseEeg, aEegPort, aUseEcg, aEcgFilter,
        aLogTarget, aLogFormat,
        aBreathEnabled, aBreathOnlyOutput,
        aBreathMinDelta, aBreathMaxRr, aEegStaleSec, aFullScan,
        parseError);

    if not Result then
        TLogCore.writeErrorLine(nil, 'ERROR: ' + parseError);
end;

{*******************************************************************************
* hasHelpArg
*******************************************************************************}
function hasHelpArg(): Boolean;
var
    i: Integer;
    arg: string;
begin
    Result := False;

    for i := 1 to ParamCount do
    begin
        arg := LowerCase(Trim(ParamStr(i)));
        if (arg = '-h') or (arg = '--help') then
        begin
            Result := True;
            Exit;
        end;
    end;
end;

{*******************************************************************************
* hasListDevicesArg
*******************************************************************************}
function hasListDevicesArg(): Boolean;
var
    i: Integer;
    arg: string;
begin
    Result := False;

    for i := 1 to ParamCount do
    begin
        arg := LowerCase(Trim(ParamStr(i)));
        if arg = '--list-devices' then
        begin
            Result := True;
            Exit;
        end;
    end;
end;

function parsePingDeviceArg(out aMac: string; out aFound: Boolean): Boolean;
var
    i: Integer;
    arg: string;
    lowerArg: string;
    valueText: string;
begin
    Result := True;
    aFound := False;
    aMac := '';

    for i := 1 to ParamCount do
    begin
        arg := Trim(ParamStr(i));
        lowerArg := LowerCase(arg);

        if lowerArg = '--ping-device' then
        begin
            aFound := True;
            if i >= ParamCount then
            begin
                Result := False;
                Exit;
            end;

            valueText := Trim(ParamStr(i + 1));
            if valueText = '' then
            begin
                Result := False;
                Exit;
            end;

            aMac := valueText;
            Exit;
        end;

        if Pos('--ping-device=', lowerArg) = 1 then
        begin
            aFound := True;
            valueText := Trim(Copy(arg, Length('--ping-device=') + 1, MaxInt));
            if valueText = '' then
            begin
                Result := False;
                Exit;
            end;

            aMac := valueText;
            Exit;
        end;
    end;
end;

function parseDiagnoseEegArg(out aMac: string; out aFound: Boolean): Boolean;
var
    i: Integer;
    arg: string;
    lowerArg: string;
    valueText: string;
begin
    Result := True;
    aFound := False;
    aMac := '';

    for i := 1 to ParamCount do
    begin
        arg := Trim(ParamStr(i));
        lowerArg := LowerCase(arg);

        if Pos('--diagnose-eeg=', lowerArg) = 1 then
        begin
            aFound := True;
            valueText := Trim(Copy(arg, Length('--diagnose-eeg=') + 1, MaxInt));
            if valueText = '' then
            begin
                Result := False;
                Exit;
            end;

            aMac := valueText;
            Exit;
        end;
    end;
end;

function parseProbeDeviceArg(out aMac: string; out aFound: Boolean): Boolean;
var
    i: Integer;
    arg: string;
    lowerArg: string;
    valueText: string;
begin
    Result := True;
    aFound := False;
    aMac := '';

    for i := 1 to ParamCount do
    begin
        arg := Trim(ParamStr(i));
        lowerArg := LowerCase(arg);

        if lowerArg = '--probe-device' then
        begin
            aFound := True;
            if i >= ParamCount then
            begin
                Result := False;
                Exit;
            end;

            valueText := Trim(ParamStr(i + 1));
            if valueText = '' then
            begin
                Result := False;
                Exit;
            end;

            aMac := valueText;
            Exit;
        end;

        if Pos('--probe-device=', lowerArg) = 1 then
        begin
            aFound := True;
            valueText := Trim(Copy(arg, Length('--probe-device=') + 1, MaxInt));
            if valueText = '' then
            begin
                Result := False;
                Exit;
            end;

            aMac := valueText;
            Exit;
        end;
    end;
end;

function hasCsvColumnsArg(): Boolean;
var
    i: Integer;
    arg: string;
begin
    Result := False;

    for i := 1 to ParamCount do
    begin
        arg := LowerCase(Trim(ParamStr(i)));
        if (arg = '--csv-columns') or (Pos('--csv-columns=', arg) = 1) then
        begin
            Result := True;
            Exit;
        end;
    end;
end;


{*******************************************************************************
* hasStdioArg
*******************************************************************************}
function hasStdioArg(): Boolean;
var
    i: Integer;
begin
    Result := False;
    for i := 1 to ParamCount do
        if LowerCase(Trim(ParamStr(i))) = '--stdio' then
        begin
            Result := True;
            Exit;
        end;
end;

{*******************************************************************************
* hasServerArg
*******************************************************************************}
function hasServerArg(): Boolean;
var
    i: Integer;
begin
    Result := False;
    for i := 1 to ParamCount do
        if LowerCase(Trim(ParamStr(i))) = '--server' then
        begin
            Result := True;
            Exit;
        end;
end;

{*******************************************************************************
* parseProbeWorkersArg
*******************************************************************************}
function parseProbeWorkersArg(): Boolean;
var
    i: Integer;
    arg: string;
    valueText: string;
    probeWorkerCount: Integer;
begin
    Result := True;
    gListDevicesProbeWorkerCount := AUTO_LIST_DEVICES_PROBE_WORKER_COUNT;

    i := 1;
    while i <= ParamCount do
    begin
        arg := LowerCase(Trim(ParamStr(i)));

        if arg = '--probe-workers' then
        begin
            if i < ParamCount then
            begin
                valueText := Trim(ParamStr(i + 1));
                if not tryParsePositiveIntegerOptionValue(valueText, 1,
                    probeWorkerCount) then
                begin
                    TLogCore.writeErrorLine(nil,
                        'ERROR: --probe-workers requires an integer >= 1.');
                    Exit(False);
                end;

                gListDevicesProbeWorkerCount := probeWorkerCount;
                Inc(i, 2);
                Continue;
            end;

            TLogCore.writeErrorLine(nil,
                'ERROR: --probe-workers requires an integer value.');
            Exit(False);
        end;

        if Pos('--probe-workers=', arg) = 1 then
        begin
            valueText := Trim(Copy(ParamStr(i), Pos('=', ParamStr(i)) + 1,
                MaxInt));
            if not tryParsePositiveIntegerOptionValue(valueText, 1,
                probeWorkerCount) then
            begin
                TLogCore.writeErrorLine(nil,
                    'ERROR: --probe-workers requires an integer >= 1.');
                Exit(False);
            end;

            gListDevicesProbeWorkerCount := probeWorkerCount;
            Inc(i);
            Continue;
        end;

        Inc(i);
    end;
end;

{*******************************************************************************
* parseKeepAliveSecArg
*******************************************************************************}
function parseKeepAliveSecArg(out aKeepAliveSec: Integer): Boolean;
var
    i: Integer;
    arg: string;
    valueText: string;
begin
    Result := True;
    aKeepAliveSec := 15;

    i := 1;
    while i <= ParamCount do
    begin
        arg := LowerCase(Trim(ParamStr(i)));

        if arg = '--keep-alive-sec' then
        begin
            if i < ParamCount then
            begin
                valueText := Trim(ParamStr(i + 1));
                if (not TryStrToInt(valueText, aKeepAliveSec)) or
                    (aKeepAliveSec <= 0) then
                begin
                    TLogCore.writeErrorLine(nil,
                        'ERROR: --keep-alive-sec requires an integer > 0.');
                    Exit(False);
                end;
                Inc(i, 2);
                Continue;
            end;

            TLogCore.writeErrorLine(nil,
                'ERROR: --keep-alive-sec requires an integer value.');
            Exit(False);
        end;

        if Pos('--keep-alive-sec=', arg) = 1 then
        begin
            valueText := Trim(Copy(ParamStr(i), Pos('=', ParamStr(i)) + 1, MaxInt));
            if (not TryStrToInt(valueText, aKeepAliveSec)) or
                (aKeepAliveSec <= 0) then
            begin
                TLogCore.writeErrorLine(nil,
                    'ERROR: --keep-alive-sec requires an integer > 0.');
                Exit(False);
            end;
            Inc(i);
            Continue;
        end;

        Inc(i);
    end;
end;

{*******************************************************************************
* hasInitBleArg
*******************************************************************************}
function hasInitBleArg(): Boolean;
var
    i: Integer;
begin
    Result := False;
    for i := 1 to ParamCount do
        if LowerCase(Trim(ParamStr(i))) = '--init-ble' then
        begin
            Result := True;
            Exit;
        end;
end;

{*******************************************************************************
* tryReadStdinLineWithTimeout
*******************************************************************************}
function tryReadStdinLineWithTimeout(out aLine: string;
    aTimeoutMs: DWORD; out aReachedEof: Boolean): Boolean;
var
    ok: BOOL;
    waitRes: DWORD;
    bytesAvail: DWORD;
    stdinHandle: THandle;
begin
    Result := False;
    aLine := '';
    aReachedEof := False;
    stdinHandle := GetStdHandle(STD_INPUT_HANDLE);

    if stdinHandle = INVALID_HANDLE_VALUE then
    begin
        aReachedEof := True;
        Exit;
    end;

    if GetFileType(stdinHandle) <> FILE_TYPE_PIPE then
    begin
        Result := readStdinLine(aLine);
        aReachedEof := not Result;
        Exit;
    end;

    waitRes := WaitForSingleObject(stdinHandle, aTimeoutMs);
    if waitRes = WAIT_TIMEOUT then
        Exit;

    if waitRes <> WAIT_OBJECT_0 then
    begin
        aReachedEof := True;
        Exit;
    end;

    bytesAvail := 0;
    ok := PeekNamedPipe(stdinHandle, nil, 0, nil, @bytesAvail, nil);
    if not ok then
    begin
        aReachedEof := GetLastError() = ERROR_BROKEN_PIPE;
        Exit;
    end;

    if bytesAvail = 0 then
    begin
        // Some PTY/pipe setups can report WAIT_OBJECT_0 with no readable bytes.
        // Sleep for the caller timeout to avoid a hot spin in server loops.
        if aTimeoutMs > 0 then
            Sleep(aTimeoutMs);
        Exit;
    end;

    Result := readStdinLine(aLine);
    aReachedEof := not Result;
end;

{*******************************************************************************
* TStdioCommandLoop.Create
*******************************************************************************}
constructor TStdioCommandLoop.Create();
begin
    inherited Create;
    SetLength(Fparams, 0);
    Flogger := nil;
    FeegApp := nil;
    FecgApp := nil;
    FeegThread := nil;
    FecgThread := nil;
    FisRunning := False;
end;

{*******************************************************************************
* TStdioCommandLoop.Destroy
*******************************************************************************}
destructor TStdioCommandLoop.Destroy();
begin
    stopWorkers();
    inherited Destroy;
end;

{*******************************************************************************
* TStdioCommandLoop.parseModeArgsFromList
*   Parses Fparams array into mode settings. Mirrors parseModeArgs logic.
*******************************************************************************}
function TStdioCommandLoop.parseModeArgsFromList(out aUseEeg: Boolean;
    out aEegPort: AnsiString; out aUseEcg: Boolean;
    out aEcgFilter: string; out aLogTarget: string;
    out aLogFormat: TLogOutputFormat;
    out aBreathEnabled: Boolean; out aBreathOnlyOutput: Boolean;
    out aBreathMinDelta: Double; out aBreathMaxRr: Double;
    out aEegStaleSec: Integer;
    out aFullScan: Boolean): Boolean;
var
    parseError: string;
begin
    Result := parseModeArgsCore(Fparams, False, @reportUnknownStdioArg,
        aUseEeg, aEegPort, aUseEcg, aEcgFilter,
        aLogTarget, aLogFormat,
        aBreathEnabled, aBreathOnlyOutput,
        aBreathMinDelta, aBreathMaxRr, aEegStaleSec, aFullScan,
        parseError);

    if not Result then
        writeStdoutLine('{"event":"stdio_parse_error","message":"' +
            jsonEscape(parseError) + '"}');
end;

{*******************************************************************************
* TStdioCommandLoop.applySetParam
*   Updates or appends a single param in Fparams. Handles --log (2-token).
*******************************************************************************}
procedure TStdioCommandLoop.applySetParam(const aKey: string;
    const aValue: string);
var
    i: Integer;
    prefix: string;
    keyLower: string;
begin
    keyLower := LowerCase(aKey);

    if keyLower = '--log' then
    begin
        for i := 0 to Length(Fparams) - 2 do
        begin
            if LowerCase(Fparams[i]) = '--log' then
            begin
                Fparams[i + 1] := aValue;
                Exit;
            end;
        end;
        SetLength(Fparams, Length(Fparams) + 2);
        Fparams[High(Fparams) - 1] := '--log';
        Fparams[High(Fparams)] := aValue;
        Exit;
    end;

    prefix := keyLower + '=';
    for i := 0 to High(Fparams) do
    begin
        if (LowerCase(Fparams[i]) = keyLower) or
            (Pos(prefix, LowerCase(Fparams[i])) = 1) then
        begin
            if aValue = '' then
                Fparams[i] := aKey
            else
                Fparams[i] := aKey + '=' + aValue;
            Exit;
        end;
    end;

    SetLength(Fparams, Length(Fparams) + 1);
    if aValue = '' then
        Fparams[High(Fparams)] := aKey
    else
        Fparams[High(Fparams)] := aKey + '=' + aValue;
end;

{*******************************************************************************
* TStdioCommandLoop.writeParamUpdatedEvent
*******************************************************************************}
procedure TStdioCommandLoop.writeParamUpdatedEvent(const aKey: string;
    const aValue: string);
var
    valueText: string;
    eventText: string;
begin
    valueText := Trim(aValue);
    if valueText = '' then
        valueText := 'true';

    eventText := '{' + jsonLogTimestamp('br') +
        ',"event":"param_updated"' +
        ',"scope":"runtime"' +
        ',"level":"info"' +
        ',"key":"' + jsonEscape(aKey) + '"' +
        ',"value":"' + jsonEscape(valueText) + '"' +
        ',"message":"Parameter updated successfully"}';

    if Flogger <> nil then
    begin
        Flogger.pushLine(eventText);
        Flogger.flush;
    end
    else
        writeStdoutLine(eventText);
end;

{*******************************************************************************
* TStdioCommandLoop.applyRuntimeParam
*******************************************************************************}
function TStdioCommandLoop.applyRuntimeParam(const aKey: string;
    const aValue: string; out aErrorText: string): Boolean;
var
    staleSec: Integer;
    maxRr: Double;
    enabled: Boolean;
    minDelta: Double;
    parsedNumber: Double;
    valueText: string;
    normalizedValue: string;
    keyLower: string;
begin
    Result := True;
    aErrorText := '';

    if not FisRunning then
        Exit;

    keyLower := LowerCase(Trim(aKey));
    valueText := Trim(aValue);
    normalizedValue := valueText;

    if keyLower = '--eeg-stale-sec' then
    begin
        if not tryParsePositiveIntegerOptionValue(valueText, 1, staleSec) then
        begin
            aErrorText := 'Invalid --eeg-stale-sec value "' + valueText +
                '" (expected integer >= 1).';
            Result := False;
            Exit;
        end;

        normalizedValue := IntToStr(staleSec);
        if FeegApp = nil then
            Exit;

        FeegApp.EegStaleSec := staleSec;
        writeParamUpdatedEvent(aKey, normalizedValue);
        Exit;
    end;

    if FecgApp = nil then
        Exit;

    enabled := FecgApp.BreathDetectionEnabled;
    minDelta := FecgApp.BreathMinDeltaMs;
    maxRr := FecgApp.BreathMaxRrMs;

    if keyLower = '--breath' then
    begin
        if (valueText = '') or (LowerCase(valueText) = 'true') then
        begin
            enabled := True;
            normalizedValue := 'true';
        end
        else if LowerCase(valueText) = 'false' then
        begin
            enabled := False;
            normalizedValue := 'false';
        end
        else
        begin
            aErrorText := 'Invalid --breath value "' + valueText +
                '" (expected true or false).';
            Result := False;
            Exit;
        end;
    end
    else if keyLower = '--breath-min-delta' then
    begin
        if not tryParseFloatOptionValue(valueText, 0.0, parsedNumber) then
        begin
            aErrorText := 'Invalid --breath-min-delta value "' + valueText +
                '" (expected number > 0).';
            Result := False;
            Exit;
        end;

        minDelta := parsedNumber;
        normalizedValue := valueText;
    end
    else if keyLower = '--breath-rr-max' then
    begin
        if not tryParseFloatOptionValue(valueText, 300.0, parsedNumber) then
        begin
            aErrorText := 'Invalid --breath-rr-max value "' + valueText +
                '" (expected number > 300).';
            Result := False;
            Exit;
        end;

        maxRr := parsedNumber;
        normalizedValue := valueText;
    end
    else
        Exit;

    FecgApp.updateBreathSettings(enabled, minDelta, maxRr);
    writeParamUpdatedEvent(aKey, normalizedValue);
end;

{*******************************************************************************
* TStdioCommandLoop.prepareEcgApp
*******************************************************************************}
procedure TStdioCommandLoop.prepareEcgApp(aEcgApp: THeartRateReader;
    const aEcgFilter: string; aFullScan: Boolean);
begin
    preScanEcg(aEcgApp, aEcgFilter, aFullScan, Flogger);
end;

{*******************************************************************************
* TStdioCommandLoop.startWorkers
*   Parses Fparams and starts EEG/ECG worker threads.
*******************************************************************************}
procedure TStdioCommandLoop.startWorkers();
var
    useEeg: Boolean;
    useEcg: Boolean;
    eegStaleSec: Integer;
    logTarget: string;
    logFormat: TLogOutputFormat;
    breathEnabled: Boolean;
    breathOnlyOutput: Boolean;
    breathMinDelta: Double;
    breathMaxRr: Double;
    eegPort: AnsiString;
    ecgFilter: string;
    fullScan: Boolean;
begin
    if not parseModeArgsFromList(useEeg, eegPort, useEcg, ecgFilter,
        logTarget, logFormat, breathEnabled,
        breathOnlyOutput, breathMinDelta, breathMaxRr, eegStaleSec,
        fullScan) then
    begin
        writeStdoutLine('{"event":"stdio_start_error","message":"Parameter parse failed"}');
        Exit;
    end;

    if logTarget <> '' then
        Flogger := TLogCore.Create(logTarget, logFormat);

    if useEeg then
    begin
        eegPort := resolveEegPort(eegPort, Flogger);
        if string(eegPort) = '' then
        begin
            writeStdoutLine('{"event":"stdio_start_error","message":"EEG port resolve failed"}');
            FreeAndNil(Flogger);
            Exit;
        end;
    end;

    if useEcg then
    begin
        FecgApp := THeartRateReader.Create();
        FecgApp.BreathDetectionEnabled := breathEnabled;
        FecgApp.BreathOnlyOutput := breathOnlyOutput;
        FecgApp.BreathMinDeltaMs := breathMinDelta;
        FecgApp.BreathMaxRrMs := breathMaxRr;
        FecgApp.FullScan := fullScan;
        if Flogger <> nil then
            FecgApp.Logger := Flogger;
        prepareEcgApp(FecgApp, ecgFilter, fullScan);
        FecgThread := TEcgReaderThread.Create(FecgApp, ecgFilter);
    end;

    if useEeg then
    begin
        FeegApp := TBodyMonitorCore.Create();
        FeegApp.EegStaleSec := eegStaleSec;
        if Flogger <> nil then
            FeegApp.Logger := Flogger;
        FeegThread := TEegReaderThread.Create(FeegApp, eegPort);
    end;

    if FeegThread <> nil then
        FeegThread.Start();
    if FecgThread <> nil then
        FecgThread.Start();

    FisRunning := True;
end;

{*******************************************************************************
* TStdioCommandLoop.stopWorkers
*   Signals worker threads to stop and waits for them to finish.
*******************************************************************************}
procedure TStdioCommandLoop.stopWorkers();
begin
    if not FisRunning then
        Exit;

    if FeegApp <> nil then
        FeegApp.stop();
    if FecgApp <> nil then
        FecgApp.stop();

    if FeegThread <> nil then
        FeegThread.WaitFor();
    if FecgThread <> nil then
        FecgThread.WaitFor();

    FreeAndNil(FeegThread);
    FreeAndNil(FecgThread);
    FreeAndNil(FeegApp);
    FreeAndNil(FecgApp);

    if Flogger <> nil then
    begin
        Flogger.finish;
        FreeAndNil(Flogger);
    end;

    FisRunning := False;
end;

{*******************************************************************************
* TStdioCommandLoop.run
*   Main stdin command loop. Reads JSONL commands until quit or EOF.
*******************************************************************************}
procedure TStdioCommandLoop.run();
var
    line: string;
    cmd: TStdioCommand;
    paramError: string;
begin
    writeStdoutLine('{"event":"stdio_ready"}');

    while readStdinLine(line) do
    begin
        line := Trim(line);
        if line = '' then
            Continue;

        if not parseStdioCommand(line, cmd) or (cmd.CmdType = sctUnknown) then
        begin
            writeStdoutLine(makeStdioAck('unknown', False, 'Unknown or malformed command'));
            Continue;
        end;

        case cmd.CmdType of
            sctConfigure:
            begin
                Fparams := cmd.Params;
                writeStdoutLine(makeStdioAck('configure', True));
            end;

            sctStart:
            begin
                if FisRunning then
                    writeStdoutLine(makeStdioAck('start', False, 'Already running'))
                else
                begin
                    startWorkers();
                    if FisRunning then
                        writeStdoutLine(makeStdioAck('start', True))
                    else
                        writeStdoutLine(makeStdioAck('start', False, 'Failed to start workers'));
                end;
            end;

            sctStop:
            begin
                stopWorkers();
                writeStdoutLine(makeStdioAck('stop', True));
            end;

            sctSetParam:
            begin
                applySetParam(cmd.ParamKey, cmd.ParamValue);
                if applyRuntimeParam(cmd.ParamKey, cmd.ParamValue,
                    paramError) then
                    writeStdoutLine(makeStdioAck('set_param', True))
                else
                    writeStdoutLine(makeStdioAck('set_param', False,
                        paramError));
            end;

            sctQuit:
            begin
                stopWorkers();
                writeStdoutLine(makeStdioAck('quit', True));
                Break;
            end;
        end;
    end;
end;

{*******************************************************************************
* TServerCommandLoop.Create
*******************************************************************************}
constructor TServerCommandLoop.Create(aKeepAliveSec: Integer; aInitBle: Boolean);
begin
    inherited Create();
    FkeepAliveSec := aKeepAliveSec;
    FinitBle := aInitBle;
    FcacheBleLoaded := False;
    FlistDevicesThread := nil;
    FlistDevicesCanceled := False;
    FlastPingTick := GetTickCount64();
    SetLength(FcachedDevices, 0);
end;

{*******************************************************************************
* TServerCommandLoop.Destroy
*******************************************************************************}
destructor TServerCommandLoop.Destroy();
begin
    cancelListDevicesScan('shutdown');
    if FlistDevicesThread <> nil then
    begin
        FlistDevicesThread.WaitFor();
        FlistDevicesThread.cleanupRetainedHandles();
        FreeAndNil(FlistDevicesThread);
    end;

    clearCachedDevices(True);
    inherited Destroy();
end;

{*******************************************************************************
* TServerCommandLoop.cancelListDevicesScan
*******************************************************************************}
procedure TServerCommandLoop.cancelListDevicesScan(const aReason: string = '');
begin
    if FlistDevicesThread = nil then
        Exit;

    FlistDevicesCanceled := True;
    FlistDevicesThread.requestCancel();
    if aReason <> '' then
        writeStdoutLine('{"event":"list_devices_cancelled","reason":"' +
            jsonEscape(aReason) + '"}');
end;

{*******************************************************************************
* TServerCommandLoop.clearCachedDevices
*******************************************************************************}
procedure TServerCommandLoop.clearCachedDevices(aUnloadBle: Boolean = True);
begin
    releaseScannedDeviceArray(FcachedDevices);

    if FcacheBleLoaded and aUnloadBle then
    begin
        SimpleBleUnloadLibrary();
        FcacheBleLoaded := False;
    end;
end;

{*******************************************************************************
* TServerCommandLoop.releaseListDevicesThread
*******************************************************************************}
procedure TServerCommandLoop.releaseListDevicesThread();
begin
    FreeAndNil(FlistDevicesThread);
    FlistDevicesCanceled := False;
end;

{*******************************************************************************
* TServerCommandLoop.finishListDevicesFailure
*******************************************************************************}
procedure TServerCommandLoop.finishListDevicesFailure(
    const aErrorText: string);
begin
    if FlistDevicesThread <> nil then
        FlistDevicesThread.cleanupRetainedHandles();

    writeStdoutLine(makeStdioAck('list_devices', False, aErrorText));
    releaseListDevicesThread();
end;

{*******************************************************************************
* TServerCommandLoop.pollListDevicesThread
*******************************************************************************}
procedure TServerCommandLoop.pollListDevicesThread();
var
    waitRes: DWORD;
    scanResult: TDeviceScanResult;
    errorText: string;
begin
    if FlistDevicesThread = nil then
        Exit;

    waitRes := WaitForSingleObject(FlistDevicesThread.Handle, 0);
    if waitRes <> WAIT_OBJECT_0 then
        Exit;

    FlistDevicesThread.WaitFor();

    if FlistDevicesCanceled then
    begin
        finishListDevicesFailure('Cancelled');
        Exit;
    end;

    if not FlistDevicesThread.Success then
    begin
        errorText := Trim(FlistDevicesThread.ErrorMessage);
        if errorText = '' then
            errorText := 'BLE scan failed';

        finishListDevicesFailure(errorText);
        Exit;
    end;

    clearCachedDevices(True);
    scanResult := FlistDevicesThread.ScanResult;
    FcachedDevices := scanResult.Devices;
    FcacheBleLoaded := scanResult.BleLibraryLoaded;

    writeStdoutLine('{"event":"list_devices_done","count":' +
        IntToStr(Length(FcachedDevices)) + '}');
    writeStdoutLine(makeStdioAck('list_devices', True));

    releaseListDevicesThread();
end;

{*******************************************************************************
* TServerCommandLoop.warmupBleStack
*******************************************************************************}
procedure TServerCommandLoop.warmupBleStack();
var
    errMsg: string;
    adapter: TSimpleBleAdapter;
begin
    if FcacheBleLoaded then
        Exit;

    if not initBleAdapter(adapter, errMsg) then
    begin
        writeStdoutLine('{"event":"ble_init","ok":false,"error":"' +
            jsonEscape(errMsg) + '"}');
        Exit;
    end;

    if adapter <> 0 then
        SimpleBleAdapterReleaseHandle(adapter);

    FcacheBleLoaded := True;
    writeStdoutLine('{"event":"ble_init","ok":true}');
end;

{*******************************************************************************
* TServerCommandLoop.handleListDevices
*******************************************************************************}
procedure TServerCommandLoop.handleListDevices();
begin
    if FisRunning then
    begin
        writeStdoutLine(makeStdioAck('list_devices', False, 'Stop active workers first'));
        Exit;
    end;

    if FlistDevicesThread <> nil then
    begin
        writeStdoutLine(makeStdioAck('list_devices', False, 'Scan already in progress'));
        Exit;
    end;

    clearCachedDevices(True);
    FlistDevicesCanceled := False;
    FlistDevicesThread := TListDevicesThread.Create();
    FlistDevicesThread.Start();
end;

{*******************************************************************************
* TServerCommandLoop.takeCachedPeripheral
*******************************************************************************}
function TServerCommandLoop.takeCachedPeripheral(const aMac: string;
    out aPeripheral: TSimpleBlePeripheral; out aIdentifier: string): Boolean;
var
    i: Integer;
    foundIndex: Integer;
    macNorm: string;
begin
    Result := False;
    aPeripheral := 0;
    aIdentifier := '';
    foundIndex := -1;
    macNorm := LowerCase(Trim(aMac));
    if macNorm = '' then
        Exit;

    for i := 0 to Length(FcachedDevices) - 1 do
    begin
        if LowerCase(Trim(FcachedDevices[i].Mac)) <> macNorm then
            Continue;
        if FcachedDevices[i].Peripheral = 0 then
            Continue;

        foundIndex := i;
        aPeripheral := FcachedDevices[i].Peripheral;
        aIdentifier := FcachedDevices[i].Identifier;
        Break;
    end;

    if foundIndex < 0 then
        Exit;

    for i := 0 to Length(FcachedDevices) - 1 do
    begin
        if i = foundIndex then
        begin
            resetScannedDeviceHandle(FcachedDevices[i]);
            Continue;
        end;

        releaseScannedDeviceHandle(FcachedDevices[i]);
    end;
    SetLength(FcachedDevices, 0);
    Result := True;
end;

{*******************************************************************************
* TServerCommandLoop.prepareEcgApp
*******************************************************************************}
procedure TServerCommandLoop.prepareEcgApp(aEcgApp: THeartRateReader;
    const aEcgFilter: string; aFullScan: Boolean);
var
    cachedPeripheral: TSimpleBlePeripheral;
    cachedIdentifier: string;
begin
    cachedPeripheral := 0;
    cachedIdentifier := '';
    if takeCachedPeripheral(aEcgFilter, cachedPeripheral, cachedIdentifier) then
    begin
        if cachedIdentifier <> '' then
            writeBleScanLine(Flogger, 'device_found', 'info',
                Format('Using cached Heart Rate device: %s [%s]', [
                    cachedIdentifier,
                    aEcgFilter]));
        aEcgApp.setPreScannedPeripheral(cachedPeripheral, FcacheBleLoaded,
            False);
        FcacheBleLoaded := False;
    end
    else
    begin
        clearCachedDevices(False);
        inherited prepareEcgApp(aEcgApp, aEcgFilter, aFullScan);
    end;
end;

{*******************************************************************************
* TServerCommandLoop.run
*******************************************************************************}
procedure TServerCommandLoop.run();
var
    eofReached: Boolean;
    line: string;
    cmd: TStdioCommand;
    paramError: string;
    nowTick: QWord;
begin
    writeStdoutLine('{"event":"server_ready"}');

    if FinitBle then
        warmupBleStack();

    while True do
    begin
        pollListDevicesThread();

        nowTick := GetTickCount64();
        if (FkeepAliveSec > 0) and
            (nowTick - FlastPingTick > QWord(FkeepAliveSec * 2000)) then
        begin
            writeStdoutLine('{"event":"server_timeout"}');
            stopWorkers();
            Break;
        end;

        if not tryReadStdinLineWithTimeout(line, 500, eofReached) then
        begin
            if eofReached then
            begin
                stopWorkers();
                Break;
            end;
            Continue;
        end;

        line := Trim(line);
        if line = '' then
            Continue;

        FlastPingTick := GetTickCount64();

        if not parseStdioCommand(line, cmd) or (cmd.CmdType = sctUnknown) then
        begin
            writeStdoutLine(makeStdioAck('unknown', False, 'Unknown or malformed command'));
            Continue;
        end;

        case cmd.CmdType of
            sctConfigure:
            begin
                Fparams := cmd.Params;
                writeStdoutLine(makeStdioAck('configure', True));
            end;

            sctListDevices:
                handleListDevices();

            sctStart:
            begin
                if FisRunning then
                    writeStdoutLine(makeStdioAck('start', False, 'Already running'))
                else if FlistDevicesThread <> nil then
                    writeStdoutLine(makeStdioAck('start', False, 'list_devices scan in progress'))
                else
                begin
                    startWorkers();
                    if FisRunning then
                        writeStdoutLine(makeStdioAck('start', True))
                    else
                        writeStdoutLine(makeStdioAck('start', False, 'Failed to start workers'));
                end;
            end;

            sctPing:
                writeStdoutLine(makeStdioAck('ping', True));

            sctStop:
            begin
                cancelListDevicesScan('stop');
                stopWorkers();
                writeStdoutLine(makeStdioAck('stop', True));
            end;

            sctSetParam:
            begin
                applySetParam(cmd.ParamKey, cmd.ParamValue);
                if applyRuntimeParam(cmd.ParamKey, cmd.ParamValue,
                    paramError) then
                    writeStdoutLine(makeStdioAck('set_param', True))
                else
                    writeStdoutLine(makeStdioAck('set_param', False,
                        paramError));
            end;

            sctQuit:
            begin
                cancelListDevicesScan('quit');
                if FlistDevicesThread <> nil then
                begin
                    FlistDevicesThread.WaitFor();
                    pollListDevicesThread();
                end;

                stopWorkers();
                writeStdoutLine(makeStdioAck('quit', True));
                Break;
            end;
        end;

        FlastPingTick := GetTickCount64();
    end;
end;

var
    ecgApp: THeartRateReader;
    eegApp: TBodyMonitorCore;
    initBle: Boolean;
    keepAliveSec: Integer;
    serverCmdLoop: TServerCommandLoop;
    stdioCmdLoop: TStdioCommandLoop;
    ecgThread: TEcgReaderThread;
    eegThread: TEegReaderThread;
    logger: TLogCore;
    useEeg: Boolean;
    useEcg: Boolean;
    logTarget: string;
    logFormat: TLogOutputFormat;
    breathEnabled: Boolean;
    eegStaleSec: Integer;
    breathMaxRr: Double;
    breathOnlyOutput: Boolean;
    breathMinDelta: Double;
    eegPort: AnsiString;
    fullScan: Boolean;
    ecgFilter: string;
    pingMac: string;
    probeMac: string;
    diagEegMac: string;
    logFormatSpecified: Boolean;
    pingArgFound: Boolean;
    probeArgFound: Boolean;
    diagEegArgFound: Boolean;
    pingSuccess: Boolean;
    probeSuccess: Boolean;
    diagEegSuccess: Boolean;
begin
    eegApp := nil;
    ecgApp := nil;
    logger := nil;
    eegThread := nil;
    ecgThread := nil;
    serverCmdLoop := nil;
    try
        ExitCode := 0;
        try
            if ParamCount() < 1 then
            begin
                printUsage;
                ExitCode := 0;
            end
            else if hasHelpArg() then
            begin
                printUsage;
                ExitCode := 0;
            end
            else if not parseProbeWorkersArg() then
            begin
                ExitCode := 1;
                Exit;
            end
            else if hasStdioArg() then
            begin
                stdioCmdLoop := TStdioCommandLoop.Create();
                try
                    stdioCmdLoop.run();
                finally
                    FreeAndNil(stdioCmdLoop);
                end;
                ExitCode := 0;
            end
            else if hasServerArg() then
            begin
                if not parseKeepAliveSecArg(keepAliveSec) then
                begin
                    ExitCode := 1;
                    Exit;
                end;

                initBle := hasInitBleArg();
                serverCmdLoop := TServerCommandLoop.Create(keepAliveSec, initBle);
                try
                    serverCmdLoop.run();
                finally
                    FreeAndNil(serverCmdLoop);
                end;
                ExitCode := 0;
            end
            else if not parsePingDeviceArg(pingMac, pingArgFound) then
            begin
                TLogCore.writeErrorLine(nil,
                    'ERROR: --ping-device requires a non-empty MAC value.');
                printUsage;
                ExitCode := 1;
            end
            else if pingArgFound then
            begin
                logTarget := '';
                logFormat := LOG_FORMAT_PLAIN;
                logFormatSpecified := False;
                try
                    TLogCore.parseLogArg(logTarget);
                    logFormatSpecified := TLogCore.parseLogFormatArg(logFormat);
                    if hasCsvColumnsArg() then
                        raise Exception.Create('--csv-columns is no longer supported.');
                except
                    on E: Exception do
                    begin
                        TLogCore.writeErrorLine(nil, 'ERROR: ' + E.Message);
                        printUsage;
                        ExitCode := 1;
                        Exit;
                    end;
                end;

                if logFormatSpecified and (logTarget = '') then
                    logTarget := '-';

                if logTarget <> '' then
                    logger := TLogCore.Create(logTarget, logFormat);

                pingDevice(pingMac, logger, pingSuccess);
                if pingSuccess then
                    ExitCode := 0
                else
                    ExitCode := 1;
            end
            else if not parseDiagnoseEegArg(diagEegMac, diagEegArgFound) then
            begin
                TLogCore.writeErrorLine(nil,
                    'ERROR: --diagnose-eeg requires a non-empty MAC value.');
                printUsage;
                ExitCode := 1;
            end
            else if diagEegArgFound then
            begin
                logTarget := '';
                logFormat := LOG_FORMAT_PLAIN;
                logFormatSpecified := False;
                try
                    TLogCore.parseLogArg(logTarget);
                    logFormatSpecified := TLogCore.parseLogFormatArg(logFormat);
                except
                    on E: Exception do
                    begin
                        TLogCore.writeErrorLine(nil, 'ERROR: ' + E.Message);
                        printUsage;
                        ExitCode := 1;
                        Exit;
                    end;
                end;

                if logFormatSpecified and (logTarget = '') then
                    logTarget := '-';

                if logTarget <> '' then
                    logger := TLogCore.Create(logTarget, logFormat);

                diagnoseEeg(diagEegMac, logger, diagEegSuccess);
                if diagEegSuccess then
                    ExitCode := 0
                else
                    ExitCode := 1;
            end
            else if not parseProbeDeviceArg(probeMac, probeArgFound) then
            begin
                TLogCore.writeErrorLine(nil,
                    'ERROR: --probe-device requires a non-empty MAC value.');
                printUsage;
                ExitCode := 1;
            end
            else if probeArgFound then
            begin
                logTarget := '';
                logFormat := LOG_FORMAT_PLAIN;
                logFormatSpecified := False;
                try
                    TLogCore.parseLogArg(logTarget);
                    logFormatSpecified := TLogCore.parseLogFormatArg(logFormat);
                    if hasCsvColumnsArg() then
                        raise Exception.Create('--csv-columns is no longer supported.');
                except
                    on E: Exception do
                    begin
                        TLogCore.writeErrorLine(nil, 'ERROR: ' + E.Message);
                        printUsage;
                        ExitCode := 1;
                        Exit;
                    end;
                end;

                if logFormatSpecified and (logTarget = '') then
                    logTarget := '-';

                if logTarget <> '' then
                    logger := TLogCore.Create(logTarget, logFormat);

                probeDevice(probeMac, logger, probeSuccess);
                if probeSuccess then
                    ExitCode := 0
                else
                    ExitCode := 1;
            end
            else if hasListDevicesArg() then
            begin
                logTarget := '';
                logFormat := LOG_FORMAT_PLAIN;
                logFormatSpecified := False;
                try
                    TLogCore.parseLogArg(logTarget);
                    logFormatSpecified := TLogCore.parseLogFormatArg(logFormat);
                    if hasCsvColumnsArg() then
                        raise Exception.Create('--csv-columns is no longer supported.');
                except
                    on E: Exception do
                    begin
                        TLogCore.writeErrorLine(nil, 'ERROR: ' + E.Message);
                        printUsage;
                        ExitCode := 1;
                        Exit;
                    end;
                end;

                if logFormatSpecified and (logTarget = '') then
                    logTarget := '-';

                if logTarget <> '' then
                    logger := TLogCore.Create(logTarget, logFormat);

                printListDevices(logger);
                ExitCode := 0;
            end
            else if not parseModeArgs(useEeg, eegPort, useEcg, ecgFilter,
                logTarget, logFormat, breathEnabled,
                breathOnlyOutput, breathMinDelta, breathMaxRr, eegStaleSec,
                fullScan) then
            begin
                printUsage;
                ExitCode := 1;
            end
            else
            begin
                if logTarget <> '' then
                    logger := TLogCore.Create(logTarget, logFormat);

                if useEeg then
                begin
                    eegPort := resolveEegPort(eegPort, logger);
                    if string(eegPort) = '' then
                    begin
                        ExitCode := 1;
                        Exit;
                    end;
                end;

                if useEcg then
                begin
                    ecgApp := THeartRateReader.Create();
                    ecgApp.BreathDetectionEnabled := breathEnabled;
                    ecgApp.BreathOnlyOutput := breathOnlyOutput;
                    ecgApp.BreathMinDeltaMs := breathMinDelta;
                    ecgApp.BreathMaxRrMs := breathMaxRr;
                    ecgApp.FullScan := fullScan;
                    if logger <> nil then
                        ecgApp.Logger := logger;
                    preScanEcg(ecgApp, ecgFilter, fullScan, logger);
                    ecgThread := TEcgReaderThread.Create(ecgApp, ecgFilter);
                end;

                if useEeg then
                begin
                    eegApp := TBodyMonitorCore.Create();
                    eegApp.EegStaleSec := eegStaleSec;
                    if logger <> nil then
                        eegApp.Logger := logger;
                    eegThread := TEegReaderThread.Create(eegApp, eegPort);
                end;

                registerConsoleStopTargets(eegApp, ecgApp);

                if eegThread <> nil then
                    eegThread.Start();
                if ecgThread <> nil then
                    ecgThread.Start();

                if eegThread <> nil then
                    eegThread.WaitFor();
                if ecgThread <> nil then
                    ecgThread.WaitFor();

                if (eegThread <> nil) and (eegThread.ExitCode <> 0) then
                begin
                    ExitCode := eegThread.ExitCode;
                    if eegThread.ErrorMessage <> '' then
                        TLogCore.writeConsoleLine(logger,
                            'EEG thread error: ' + eegThread.ErrorMessage);
                end;

                if (ecgThread <> nil) and (ecgThread.ExitCode <> 0) then
                begin
                    if ExitCode = 0 then
                        ExitCode := ecgThread.ExitCode;
                    if ecgThread.ErrorMessage <> '' then
                        TLogCore.writeConsoleLine(logger,
                            'ECG thread error: ' + ecgThread.ErrorMessage);
                end;
            end;

            if logger <> nil then
                logger.finish;
        except
            on E: Exception do
            begin
                ExitCode := 255;
                TLogCore.writeConsoleLine(logger,
                    'Error: ' + E.ClassName + ': ' + E.Message);
            end;
        end;
    finally
        unregisterConsoleStopTargets();
        FreeAndNil(eegThread);
        FreeAndNil(ecgThread);
        FreeAndNil(eegApp);
        FreeAndNil(ecgApp);
        FreeAndNil(logger);
    end;
end.

