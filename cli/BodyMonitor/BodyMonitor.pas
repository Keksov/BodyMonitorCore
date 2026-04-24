program BodyMonitor;

{$mode objfpc}{$H+}

uses
    SysUtils,
    Classes,
    Windows,
    SimpleBle,
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
    WriteLn('  BodyMonitor.exe [--log-format=<plain|csv|jsonl>] ...');
    WriteLn('  BodyMonitor.exe [--csv-columns=<true|false>] ...');
    WriteLn('  BodyMonitor.exe --list-devices');
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
    WriteLn('  --log-format        Log output format: plain, csv or jsonl [default: plain]');
    WriteLn('  --csv-columns       Print CSV column names before first row [default: false]');
    WriteLn('  --full-scan         Process all scanned devices (default: false for --eeg/--ecg)');
    WriteLn('  --list-devices      List all available COM port devices and exit');
    WriteLn('  --server            Start persistent Bun-controlled server mode');
    WriteLn('  --keep-alive-sec    Server keep-alive interval in seconds [default: 15]');
    WriteLn('  --init-ble          Initialize BLE stack immediately in --server mode');
    WriteLn;
    WriteLn('Examples:');
    WriteLn('  BodyMonitor.exe --list-devices');
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
*   Wrapper for writeBleDeviceInfo that also outputs legacy CSV to console.
*******************************************************************************}
procedure writeListDeviceLine(aLogger: TLogCore; aIndex: Integer;
    const aMac: string; const aIdentifier: string; const aDeviceType: string;
    const aComPort: string);
var
    csvLine: string;
begin
    if aComPort <> '' then
        csvLine := Format('%d,%s,%s,%s,com:%s', [
            aIndex, aMac, aIdentifier, aDeviceType, aComPort])
    else
        csvLine := Format('%d,%s,%s,%s', [
            aIndex, aMac, aIdentifier, aDeviceType]);

    writeBleDeviceInfo(aLogger, aIndex, aMac, aIdentifier, aDeviceType, aComPort, csvLine);
end;

{*******************************************************************************
* printListDevices
*   Scans BLE devices, classifies them by services and shows COM ports.
*   Format: <counter>,<mac>,<identifier>,<device_type>[,com:<port>]
*******************************************************************************}
procedure printListDevices(aLogger: TLogCore);
var
    i: Integer;
    scanner: TDeviceScanner;
    filters: TScanFilterArray;
    scanResult: TDeviceScanResult;
begin
    scanner := TDeviceScanner.Create(aLogger);
    try
        SetLength(filters, 0);
        if not scanner.scan(filters, True, False, False, scanResult) then
            Exit;

        for i := 0 to Length(scanResult.Devices) - 1 do
        begin
            writeListDeviceLine(aLogger,
                scanResult.Devices[i].Index,
                scanResult.Devices[i].Mac,
                scanResult.Devices[i].Identifier,
                scanResult.Devices[i].DeviceType,
                scanResult.Devices[i].ComPort);
        end;
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
        out aLogFormat: TLogOutputFormat; out aCsvColumns: Boolean;
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
    Flogger := TLogCore.Create('-', LOG_FORMAT_JSONL, False);
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
var
    filters: TScanFilterArray;
begin
    try
        SetLength(filters, 0);
        Fsuccess := Fscanner.scan(filters, True, False, True, FscanResult);
        if not Fsuccess then
            FerrMessage := 'BLE scan failed';
    except
        on E: Exception do
        begin
            Fsuccess := False;
            FerrMessage := E.ClassName + ': ' + E.Message;
        end;
    end;
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
    out aCsvColumns: Boolean; out aBreathEnabled: Boolean;
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
    aCsvColumns := False;
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
    out aCsvColumns: Boolean; out aBreathEnabled: Boolean;
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
        aLogFormat, aCsvColumns, aBreathEnabled, aBreathOnlyOutput,
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
                aErrorMessage := '--log-format requires one of: plain, jsonl, csv.';
                Exit;
            end;

            valueText := aArgs[i - 1];
            if not TLogCore.tryParseLogFormat(valueText, aLogFormat) then
            begin
                aErrorMessage := 'Invalid --log-format value: ' + valueText +
                    ' (expected plain, jsonl or csv).';
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
                aErrorMessage := '--log-format requires one of: plain, jsonl, csv.';
                Exit;
            end;

            if not TLogCore.tryParseLogFormat(valueText, aLogFormat) then
            begin
                aErrorMessage := 'Invalid --log-format value: ' + valueText +
                    ' (expected plain, jsonl or csv).';
                Exit;
            end;

            logFormatSpecified := True;
            Inc(i);
            Continue;
        end;

        if lowerArg = '--csv-columns' then
        begin
            if (i + 1 < n) and ((LowerCase(aArgs[i + 1]) = 'true') or
                (LowerCase(aArgs[i + 1]) = 'false')) then
            begin
                aCsvColumns := LowerCase(aArgs[i + 1]) = 'true';
                Inc(i, 2);
            end
            else
            begin
                aCsvColumns := True;
                Inc(i);
            end;
            Continue;
        end;

        if Pos('--csv-columns=', lowerArg) = 1 then
        begin
            eqPos := Pos('=', arg);
            valueText := LowerCase(Trim(Copy(arg, eqPos + 1, MaxInt)));
            if (valueText <> 'true') and (valueText <> 'false') then
            begin
                aErrorMessage := 'Invalid --csv-columns value "' +
                    valueText + '" (expected true or false).';
                Exit;
            end;

            aCsvColumns := valueText = 'true';
            Inc(i);
            Continue;
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
    out aCsvColumns: Boolean; out aBreathEnabled: Boolean;
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
        aLogTarget, aLogFormat, aCsvColumns,
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

{*******************************************************************************
* parseCsvColumnsArg
*******************************************************************************}
function parseCsvColumnsArg(out aCsvColumns: Boolean): Boolean;
var
    i: Integer;
    arg: string;
    valueText: string;
begin
    Result := False;
    aCsvColumns := False;

    i := 1;
    while i <= ParamCount do
    begin
        arg := LowerCase(ParamStr(i));

        if arg = '--csv-columns' then
        begin
            if (i < ParamCount) and
                ((LowerCase(ParamStr(i + 1)) = 'true') or
                (LowerCase(ParamStr(i + 1)) = 'false')) then
                aCsvColumns := LowerCase(ParamStr(i + 1)) = 'true'
            else
                aCsvColumns := True;
            Result := True;
            Exit;
        end;

        if Pos('--csv-columns=', arg) = 1 then
        begin
            valueText := LowerCase(Trim(Copy(ParamStr(i), Pos('=', ParamStr(i)) + 1, MaxInt)));
            if (valueText <> 'true') and (valueText <> 'false') then
                raise Exception.Create('Invalid --csv-columns value: ' + valueText + ' (expected true or false)');
            aCsvColumns := valueText = 'true';
            Result := True;
            Exit;
        end;

        Inc(i);
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
        Exit;

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
    out aLogFormat: TLogOutputFormat; out aCsvColumns: Boolean;
    out aBreathEnabled: Boolean; out aBreathOnlyOutput: Boolean;
    out aBreathMinDelta: Double; out aBreathMaxRr: Double;
    out aEegStaleSec: Integer;
    out aFullScan: Boolean): Boolean;
var
    parseError: string;
begin
    Result := parseModeArgsCore(Fparams, False, @reportUnknownStdioArg,
        aUseEeg, aEegPort, aUseEcg, aEcgFilter,
        aLogTarget, aLogFormat, aCsvColumns,
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
    csvColumns: Boolean;
    breathEnabled: Boolean;
    breathOnlyOutput: Boolean;
    breathMinDelta: Double;
    breathMaxRr: Double;
    eegPort: AnsiString;
    ecgFilter: string;
    fullScan: Boolean;
begin
    if not parseModeArgsFromList(useEeg, eegPort, useEcg, ecgFilter,
        logTarget, logFormat, csvColumns, breathEnabled,
        breathOnlyOutput, breathMinDelta, breathMaxRr, eegStaleSec,
        fullScan) then
    begin
        writeStdoutLine('{"event":"stdio_start_error","message":"Parameter parse failed"}');
        Exit;
    end;

    if logTarget <> '' then
        Flogger := TLogCore.Create(logTarget, logFormat, csvColumns);

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

    FlistDevicesThread.emitDeviceLines();
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
    csvColumns: Boolean;
    breathEnabled: Boolean;
    eegStaleSec: Integer;
    breathMaxRr: Double;
    breathOnlyOutput: Boolean;
    breathMinDelta: Double;
    eegPort: AnsiString;
    fullScan: Boolean;
    ecgFilter: string;
    logFormatSpecified: Boolean;
    listCsvColumns: Boolean;
    listCsvSpecified: Boolean;
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
            else if hasListDevicesArg() then
            begin
                logTarget := '';
                logFormat := LOG_FORMAT_PLAIN;
                logFormatSpecified := False;
                listCsvColumns := False;
                listCsvSpecified := False;
                try
                    TLogCore.parseLogArg(logTarget);
                    logFormatSpecified := TLogCore.parseLogFormatArg(logFormat);
                    listCsvSpecified := parseCsvColumnsArg(listCsvColumns);
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
                    logger := TLogCore.Create(logTarget, logFormat,
                        listCsvSpecified and listCsvColumns);

                printListDevices(logger);
                ExitCode := 0;
            end
            else if not parseModeArgs(useEeg, eegPort, useEcg, ecgFilter,
                logTarget, logFormat, csvColumns, breathEnabled,
                breathOnlyOutput, breathMinDelta, breathMaxRr, eegStaleSec,
                fullScan) then
            begin
                printUsage;
                ExitCode := 1;
            end
            else
            begin
                if logTarget <> '' then
                    logger := TLogCore.Create(logTarget, logFormat, csvColumns);

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
        FreeAndNil(eegThread);
        FreeAndNil(ecgThread);
        FreeAndNil(eegApp);
        FreeAndNil(ecgApp);
        FreeAndNil(logger);
    end;
end.

