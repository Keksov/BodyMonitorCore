unit BodyMonitorCore;

{$mode objfpc}{$H+}

interface

uses
    SysUtils,
    Windows,
    ThinkGearSDK,
    EEGAlgoSDK,
    LogCore,
    JsonLogWriter;

type
    {***************************************************************************
     * TBodyMonitorCore
     ***************************************************************************}
    TBodyMonitorCore = class
private
    Flogger                 : TLogCore;
    FalgoRawCount           : Integer;
    FalgoEnabled            : Boolean;
    FconnectionId           : Integer;
    FalgoRawData            : array[0..511] of SmallInt;
    FstopRequested          : Boolean;
    FeegStaleSec            : Integer;
    FlastFreshEegTick       : QWord;
    FconnectedPort          : string;
    FhasSeenFreshEeg        : Boolean;
    FisEegDisconnected      : Boolean;
    FhasFreshEegSnapshot    : Boolean;

private
    procedure   setEegStaleSec(aValue: Integer);
    procedure   waitForEnter();
    function    buildAlternateComPortName(const aComPortName: string): AnsiString;
    function    hasFreshEegForSnapshot(): Boolean;
    procedure   printConnectErrorHint(aErrCode: Integer);
    function    initializeAlgoSdk(): Boolean;
    procedure   noteFreshEegData();
    procedure   resetEegFreshnessState();
    procedure   shutdownAlgoSdk();
    procedure   readAndFeedAlgoData();
    procedure   printMeasurementSnapshot();
    procedure   updateEegConnectionState();
    procedure   writeEegConnectLog(const aStage: string;
        const aLevel: string; const aPort: string; aErrCode: Integer;
        const aMessage: string);
    procedure   tryConnectUntilSuccess(const aComPortName: AnsiString);
    procedure   runContinuousRead();

public
    constructor Create();
    destructor  Destroy(); override;

    function    run(const aComPortName: AnsiString): Integer;
    procedure   stop();

    property Logger: TLogCore read Flogger write Flogger;
    property EegStaleSec: Integer read FeegStaleSec write setEegStaleSec;
    end;

implementation

var
    gAlgoLogger: TLogCore;

{*******************************************************************************
* algoSdkCallback
*******************************************************************************}
procedure algoSdkCallback(aParam: TNSKAlgoCbParam); cdecl;
var
    stateValue: Integer;
    reasonValue: Integer;
    algoTypeValue: Integer;
begin
    if aParam.cbType = NSK_ALGO_CB_TYPE_STATE then
    begin
        stateValue := aParam.param.state and NSK_ALGO_STATE_MASK;
        reasonValue := aParam.param.state and NSK_ALGO_REASON_MASK;
        TLogCore.writeConsoleLine(gAlgoLogger,
            Format('ALGO state: %s | reason: %s', [algoStateToText(stateValue), algoReasonToText(reasonValue)]));
        Exit;
    end;

    if aParam.cbType = NSK_ALGO_CB_TYPE_SIGNAL_LEVEL then
    begin
        TLogCore.writeConsoleLine(gAlgoLogger,
            Format('ALGO signal quality: %s', [algoSignalQualityToText(aParam.param.sq)]));
        Exit;
    end;

    if aParam.cbType = NSK_ALGO_CB_TYPE_ALGO then
    begin
        algoTypeValue := aParam.param.algoIndex.algoType;
        case algoTypeValue of
            NSK_ALGO_TYPE_ATT:
                TLogCore.writeConsoleLine(gAlgoLogger,
                    Format('ALGO ATT = %.0f', [aParam.param.algoIndex.value.attIndex]));
            NSK_ALGO_TYPE_MED:
                TLogCore.writeConsoleLine(gAlgoLogger,
                    Format('ALGO MED = %.0f', [aParam.param.algoIndex.value.medIndex]));
            NSK_ALGO_TYPE_BLINK:
            begin
                TLogCore.writeConsoleLine(gAlgoLogger,
                    Format('ALGO BLINK = %.0f', [aParam.param.algoIndex.value.eyeBlinkStrength]));
                if gAlgoLogger <> nil then
                    gAlgoLogger.pushLine('{' + jsonLogTimestamp('br') +
                        ',"e":"ab"' +
                        ',"sg":' + jsonLogFloat3(aParam.param.algoIndex.value.eyeBlinkStrength) + '}');
            end;
            NSK_ALGO_TYPE_BP:
            begin
                TLogCore.writeConsoleLine(gAlgoLogger,
                    Format(
                        'ALGO BP delta=%.4f theta=%.4f alpha=%.4f beta=%.4f gamma=%.4f',
                        [
                            aParam.param.algoIndex.value.bpIndex.deltaPower,
                            aParam.param.algoIndex.value.bpIndex.thetaPower,
                            aParam.param.algoIndex.value.bpIndex.alphaPower,
                            aParam.param.algoIndex.value.bpIndex.betaPower,
                            aParam.param.algoIndex.value.bpIndex.gammaPower
                        ]
                    ));
                if gAlgoLogger <> nil then
                    gAlgoLogger.pushLine('{' + jsonLogTimestamp('br') +
                        ',"e":"ap"' +
                        ',"d":' + jsonLogFloat3(aParam.param.algoIndex.value.bpIndex.deltaPower) +
                        ',"th":' + jsonLogFloat3(aParam.param.algoIndex.value.bpIndex.thetaPower) +
                        ',"a":' + jsonLogFloat3(aParam.param.algoIndex.value.bpIndex.alphaPower) +
                        ',"b":' + jsonLogFloat3(aParam.param.algoIndex.value.bpIndex.betaPower) +
                        ',"g":' + jsonLogFloat3(aParam.param.algoIndex.value.bpIndex.gammaPower) + '}');
            end;
        end;
    end;
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor TBodyMonitorCore.Create();
begin
    inherited Create;
    Flogger := nil;
    FalgoRawCount := 0;
    FalgoEnabled := False;
    FconnectionId := -1;
    FillChar(FalgoRawData, SizeOf(FalgoRawData), 0);
    FstopRequested := False;
    FeegStaleSec := 10;
    FlastFreshEegTick := 0;
    FconnectedPort := '';
    FhasSeenFreshEeg := False;
    FisEegDisconnected := False;
    FhasFreshEegSnapshot := False;
end;

{*******************************************************************************
* Destroy
*******************************************************************************}
destructor TBodyMonitorCore.Destroy();
begin
    shutdownAlgoSdk();

    if FconnectionId >= 0 then
    begin
        TG_Disconnect(FconnectionId);
        TG_FreeConnection(FconnectionId);
        FconnectionId := -1;
    end;

    inherited Destroy;
end;

{*******************************************************************************
* setEegStaleSec
*******************************************************************************}
procedure TBodyMonitorCore.setEegStaleSec(aValue: Integer);
begin
    if aValue < 1 then
        aValue := 1;

    FeegStaleSec := aValue;
end;

{*******************************************************************************
* waitForEnter
*******************************************************************************}
procedure TBodyMonitorCore.waitForEnter();
var
    userInput: string;
begin
    WriteLn;
    WriteLn('Press ENTER to exit...');
    ReadLn(userInput);
end;

{*******************************************************************************
* hasFreshEegForSnapshot
*******************************************************************************}
function TBodyMonitorCore.hasFreshEegForSnapshot(): Boolean;
begin
    Result := FhasFreshEegSnapshot;
end;

{*******************************************************************************
* buildAlternateComPortName
*******************************************************************************}
function TBodyMonitorCore.buildAlternateComPortName(const aComPortName: string): AnsiString;
var
    upperPortName: string;
begin
    upperPortName := UpperCase(aComPortName);
    if Pos('\\.\', aComPortName) = 1 then
    begin
        Result := AnsiString(Copy(aComPortName, 5, MaxInt));
        Exit;
    end;

    if Pos('COM', upperPortName) = 1 then
    begin
        Result := AnsiString('\\.\' + aComPortName);
        Exit;
    end;

    Result := '';
end;

{*******************************************************************************
* printConnectErrorHint
*******************************************************************************}
procedure TBodyMonitorCore.printConnectErrorHint(aErrCode: Integer);
begin
    case aErrCode of
        -2:
            begin
                TLogCore.writeConsoleLine(Flogger, 'Hint: TG_Connect(-2) means the COM port could not be opened.');
                TLogCore.writeConsoleLine(Flogger, 'Check that the port name is correct, the port is not busy, and the headset is paired and connected.');
                TLogCore.writeConsoleLine(Flogger, 'This SDK supports MindWave Mobile and MindWave Mobile 1.5.');
            end;
        -3:
            TLogCore.writeConsoleLine(Flogger, 'Hint: invalid baud rate passed to TG_Connect. Expected TG_BAUD_57600.');
        -4:
            TLogCore.writeConsoleLine(Flogger, 'Hint: invalid data format passed to TG_Connect. Expected TG_STREAM_PACKETS.');
    end;
end;

{*******************************************************************************
* noteFreshEegData
*******************************************************************************}
procedure TBodyMonitorCore.noteFreshEegData();
var
    msg: string;
begin
    FlastFreshEegTick := GetTickCount64();
    FhasSeenFreshEeg := True;
    FhasFreshEegSnapshot := True;

    if not FisEegDisconnected then
        Exit;

    FisEegDisconnected := False;
    msg := 'EEG data stream reconnected.';
    writeEegConnectLog('reconnected', 'info', FconnectedPort, 0, msg);
    TLogCore.writeConsoleLine(Flogger, msg);
end;

{*******************************************************************************
* resetEegFreshnessState
*******************************************************************************}
procedure TBodyMonitorCore.resetEegFreshnessState();
begin
    FlastFreshEegTick := 0;
    FhasSeenFreshEeg := False;
    FisEegDisconnected := False;
    FhasFreshEegSnapshot := False;
end;

{*******************************************************************************
* initializeAlgoSdk
*******************************************************************************}
function TBodyMonitorCore.initializeAlgoSdk(): Boolean;
var
    retCode: Integer;
    algoMask: Integer;
    sdkVersion: PAnsiChar;
    dataPathAnsi: AnsiString;
begin
    Result := False;

    FalgoRawCount := 0;
    algoMask := NSK_ALGO_TYPE_ATT or NSK_ALGO_TYPE_MED or NSK_ALGO_TYPE_BLINK or NSK_ALGO_TYPE_BP;

    retCode := NSK_ALGO_RegisterCallback(@algoSdkCallback, nil);
    if retCode <> NSK_ALGO_RET_SUCCESS then
    begin
        TLogCore.writeErrorLine(Flogger, Format('ERROR: NSK_ALGO_RegisterCallback() returned %d.', [retCode]));
        Exit;
    end;

    dataPathAnsi := AnsiString(GetCurrentDir());
    retCode := NSK_ALGO_Init(algoMask, PAnsiChar(dataPathAnsi));
    if retCode <> NSK_ALGO_RET_SUCCESS then
    begin
        TLogCore.writeErrorLine(Flogger, Format('ERROR: NSK_ALGO_Init() returned %d.', [retCode]));
        Exit;
    end;

    sdkVersion := NSK_ALGO_SdkVersion();
    if sdkVersion <> nil then
    begin
        TLogCore.writeConsoleLine(Flogger, Format('EEG Algo SDK version: %s', [string(sdkVersion)]));
    end;

    retCode := NSK_ALGO_Start(NS_FALSE);
    if retCode <> NSK_ALGO_RET_SUCCESS then
    begin
        TLogCore.writeErrorLine(Flogger, Format('ERROR: NSK_ALGO_Start() returned %d.', [retCode]));
        NSK_ALGO_Uninit();
        Exit;
    end;

    FalgoEnabled := True;
    Result := True;
end;

{*******************************************************************************
* shutdownAlgoSdk
*******************************************************************************}
procedure TBodyMonitorCore.shutdownAlgoSdk();
var
    retCode: Integer;
begin
    if FalgoEnabled = False then
    begin
        Exit;
    end;

    retCode := NSK_ALGO_Stop();
    if retCode <> NSK_ALGO_RET_SUCCESS then
    begin
        TLogCore.writeConsoleLine(Flogger, Format('WARN: NSK_ALGO_Stop() returned %d.', [retCode]));
    end;

    retCode := NSK_ALGO_Uninit();
    if retCode <> NSK_ALGO_RET_SUCCESS then
    begin
        TLogCore.writeConsoleLine(Flogger, Format('WARN: NSK_ALGO_Uninit() returned %d.', [retCode]));
    end;

    FalgoEnabled := False;
    FalgoRawCount := 0;
end;

{*******************************************************************************
* updateEegConnectionState
*******************************************************************************}
procedure TBodyMonitorCore.updateEegConnectionState();
var
    nowTick: QWord;
    staleMs: QWord;
    msg: string;
begin
    if FisEegDisconnected or (not FhasSeenFreshEeg) then
        Exit;

    nowTick := GetTickCount64();
    staleMs := QWord(FeegStaleSec) * 1000;
    if (FlastFreshEegTick = 0) or ((nowTick - FlastFreshEegTick) < staleMs) then
        Exit;

    FisEegDisconnected := True;
    msg := Format('EEG data stream disconnected after %d seconds without fresh data.',
        [FeegStaleSec]);
    writeEegConnectLog('disconnected', 'warn', FconnectedPort, 0, msg);
    TLogCore.writeConsoleLine(Flogger, msg);
end;

{*******************************************************************************
* readAndFeedAlgoData
*******************************************************************************}
procedure TBodyMonitorCore.readAndFeedAlgoData();
var
    retCode: Integer;
    pqValue: SmallInt;
    rawValue: SmallInt;
    attValue: SmallInt;
    medValue: SmallInt;
begin
    if TG_GetValueStatus(FconnectionId, TG_DATA_RAW) <> 0 then
    begin
        noteFreshEegData();
        rawValue := Trunc(TG_GetValue(FconnectionId, TG_DATA_RAW));

        if FalgoEnabled then
        begin
            FalgoRawData[FalgoRawCount] := rawValue;
            Inc(FalgoRawCount);

            if FalgoRawCount = 512 then
            begin
                retCode := NSK_ALGO_DataStream(NSK_ALGO_DATA_TYPE_EEG, @FalgoRawData[0], FalgoRawCount);
                if retCode <> NSK_ALGO_RET_SUCCESS then
                begin
                    TLogCore.writeConsoleLine(Flogger, Format('WARN: NSK_ALGO_DataStream(EEG) returned %d.', [retCode]));
                end;
                FalgoRawCount := 0;
            end;
        end;
    end;

    if FalgoEnabled then
    begin
        if TG_GetValueStatus(FconnectionId, TG_DATA_POOR_SIGNAL) <> 0 then
        begin
            noteFreshEegData();
            pqValue := Trunc(TG_GetValue(FconnectionId, TG_DATA_POOR_SIGNAL));
            retCode := NSK_ALGO_DataStream(NSK_ALGO_DATA_TYPE_PQ, @pqValue, 1);
            if retCode <> NSK_ALGO_RET_SUCCESS then
            begin
                TLogCore.writeConsoleLine(Flogger, Format('WARN: NSK_ALGO_DataStream(PQ) returned %d.', [retCode]));
            end;
        end;

        if TG_GetValueStatus(FconnectionId, TG_DATA_ATTENTION) <> 0 then
        begin
            noteFreshEegData();
            attValue := Trunc(TG_GetValue(FconnectionId, TG_DATA_ATTENTION));
            retCode := NSK_ALGO_DataStream(NSK_ALGO_DATA_TYPE_ATT, @attValue, 1);
            if retCode <> NSK_ALGO_RET_SUCCESS then
            begin
                TLogCore.writeConsoleLine(Flogger, Format('WARN: NSK_ALGO_DataStream(ATT) returned %d.', [retCode]));
            end;
        end;

        if TG_GetValueStatus(FconnectionId, TG_DATA_MEDITATION) <> 0 then
        begin
            noteFreshEegData();
            medValue := Trunc(TG_GetValue(FconnectionId, TG_DATA_MEDITATION));
            retCode := NSK_ALGO_DataStream(NSK_ALGO_DATA_TYPE_MED, @medValue, 1);
            if retCode <> NSK_ALGO_RET_SUCCESS then
            begin
                TLogCore.writeConsoleLine(Flogger, Format('WARN: NSK_ALGO_DataStream(MED) returned %d.', [retCode]));
            end;
        end;
    end;
end;

{*******************************************************************************
* printMeasurementSnapshot
*******************************************************************************}
procedure TBodyMonitorCore.printMeasurementSnapshot();
var
    vRaw: Double;
    vDelta: Double;
    vTheta: Double;
    vAlpha1: Double;
    vAlpha2: Double;
    vBeta1: Double;
    vBeta2: Double;
    vGamma1: Double;
    vGamma2: Double;
    vAttention: Double;
    vMeditation: Double;
    vPoorSignal: Double;
    snapshotText: string;
    currentTimestamp: string;
begin
    if not hasFreshEegForSnapshot() then
        Exit;

    vRaw := TG_GetValue(FconnectionId, TG_DATA_RAW);
    vPoorSignal := TG_GetValue(FconnectionId, TG_DATA_POOR_SIGNAL);
    vAttention := TG_GetValue(FconnectionId, TG_DATA_ATTENTION);
    vMeditation := TG_GetValue(FconnectionId, TG_DATA_MEDITATION);
    vDelta := TG_GetValue(FconnectionId, TG_DATA_DELTA);
    vTheta := TG_GetValue(FconnectionId, TG_DATA_THETA);
    vAlpha1 := TG_GetValue(FconnectionId, TG_DATA_ALPHA1);
    vAlpha2 := TG_GetValue(FconnectionId, TG_DATA_ALPHA2);
    vBeta1 := TG_GetValue(FconnectionId, TG_DATA_BETA1);
    vBeta2 := TG_GetValue(FconnectionId, TG_DATA_BETA2);
    vGamma1 := TG_GetValue(FconnectionId, TG_DATA_GAMMA1);
    vGamma2 := TG_GetValue(FconnectionId, TG_DATA_GAMMA2);

    currentTimestamp := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now());
    snapshotText := Format(
        'raw=%s poor_signal=%s attention=%s meditation=%s delta=%s theta=%s alpha1=%s alpha2=%s beta1=%s beta2=%s gamma1=%s gamma2=%s',
        [
            FormatFloat('0.###', vRaw),
            FormatFloat('0.###', vPoorSignal),
            FormatFloat('0.###', vAttention),
            FormatFloat('0.###', vMeditation),
            FormatFloat('0.###', vDelta),
            FormatFloat('0.###', vTheta),
            FormatFloat('0.###', vAlpha1),
            FormatFloat('0.###', vAlpha2),
            FormatFloat('0.###', vBeta1),
            FormatFloat('0.###', vBeta2),
            FormatFloat('0.###', vGamma1),
            FormatFloat('0.###', vGamma2)
        ]
    );
    TLogCore.writeConsoleLine(Flogger,
        Format('%s: %s', [currentTimestamp, snapshotText]));

    if Flogger <> nil then
        Flogger.pushLine('{' + jsonLogTimestamp('br') +
            ',"e":"s"' +
            ',"rw":' + jsonLogFloat3(vRaw) +
            ',"ps":' + jsonLogFloat3(vPoorSignal) +
            ',"at":' + jsonLogFloat3(vAttention) +
            ',"md":' + jsonLogFloat3(vMeditation) +
            ',"d":' + jsonLogFloat3(vDelta) +
            ',"th":' + jsonLogFloat3(vTheta) +
            ',"a1":' + jsonLogFloat3(vAlpha1) +
            ',"a2":' + jsonLogFloat3(vAlpha2) +
            ',"b1":' + jsonLogFloat3(vBeta1) +
            ',"b2":' + jsonLogFloat3(vBeta2) +
            ',"g1":' + jsonLogFloat3(vGamma1) +
            ',"g2":' + jsonLogFloat3(vGamma2) + '}');

    FhasFreshEegSnapshot := False;
end;

{*******************************************************************************
* writeEegConnectLog
*******************************************************************************}
procedure TBodyMonitorCore.writeEegConnectLog(const aStage: string;
    const aLevel: string; const aPort: string; aErrCode: Integer;
    const aMessage: string);
var
    line: string;
begin
    if Flogger = nil then
        Exit;
    line := '{' + jsonLogTimestamp('br') +
        ',"event":"eeg_connect"' +
        ',"source":"eeg"' +
        ',"level":"' + aLevel + '"' +
        ',"stage":"' + aStage + '"';
    if aPort <> '' then
        line := line + ',"port":"' + jsonEscape(aPort) + '"';
    if aErrCode <> 0 then
        line := line + ',"error_code":' + IntToStr(aErrCode);
    line := line + ',"message":"' + jsonEscape(aMessage) + '"}';
    Flogger.pushLine(line);
    Flogger.flush;
end;

{*******************************************************************************
* tryConnectUntilSuccess
*******************************************************************************}
procedure TBodyMonitorCore.tryConnectUntilSuccess(const aComPortName: AnsiString);
var
    msg: string;
    errCode: Integer;
    portToTry: AnsiString;
    alternatePortName: AnsiString;
begin
    alternatePortName := buildAlternateComPortName(string(aComPortName));

    msg := 'Waiting for headset connection... Press Ctrl+C to abort.';
    writeEegConnectLog('wait', 'info', '', 0, msg);
    TLogCore.writeConsoleLine(Flogger, msg);

    repeat
        portToTry := aComPortName;
        writeEegConnectLog('connect_attempt', 'info', string(portToTry), 0, 'Trying TG_Connect');
        errCode := TG_Connect(FconnectionId, PAnsiChar(portToTry), TG_BAUD_57600, TG_STREAM_PACKETS);

        if (errCode < 0) and (alternatePortName <> '') and (string(alternatePortName) <> string(aComPortName)) then
        begin
            TLogCore.writeConsoleLine(Flogger, Format('TG_Connect failed for %s (%d). Trying %s...', [string(aComPortName), errCode, string(alternatePortName)]));
            writeEegConnectLog('connect_fallback', 'warn', string(aComPortName), errCode, 'Primary port failed, trying alternate format');
            portToTry := alternatePortName;
            writeEegConnectLog('connect_attempt', 'info', string(portToTry), 0, 'Trying TG_Connect (alternate)');
            errCode := TG_Connect(FconnectionId, PAnsiChar(portToTry), TG_BAUD_57600, TG_STREAM_PACKETS);
        end;

        if errCode < 0 then
        begin
            TLogCore.writeConsoleLine(Flogger, Format('TG_Connect failed for %s (%d). Retry in 2 seconds...', [string(portToTry), errCode]));
            writeEegConnectLog('connect_failed', 'error', string(portToTry), errCode, 'TG_Connect failed, retry in 2 seconds');
            printConnectErrorHint(errCode);
            Sleep(2000);
        end;
        until (errCode >= 0) or FstopRequested;

    if FstopRequested or (errCode < 0) then
        Exit;

    FconnectedPort := string(portToTry);
    resetEegFreshnessState();
    writeEegConnectLog('connected', 'info', string(portToTry), 0, 'Connected');
    TLogCore.writeConsoleLine(Flogger, Format('Connected to %s', [string(portToTry)]));
end;

{*******************************************************************************
* runContinuousRead
*******************************************************************************}
procedure TBodyMonitorCore.runContinuousRead();
var
    errCode: Integer;
    lastPrintTick: QWord;
    packetsRead: Integer;
begin
    errCode := MWM15_setFilterType(FconnectionId, MWM15_FILTER_TYPE_50HZ);
    if errCode < 0 then
    begin
        TLogCore.writeConsoleLine(Flogger, Format('WARN: MWM15_setFilterType() returned %d.', [errCode]));
    end;

    TLogCore.writeConsoleLine(Flogger, 'Reading data... Press Ctrl+C to stop.');
    lastPrintTick := 0;

    while not FstopRequested do
    begin
        // Manual packet reads keep TG_GetValueStatus aligned with the latest packet.
        packetsRead := TG_ReadPackets(FconnectionId, 1);
        if packetsRead > 0 then
        begin
            readAndFeedAlgoData();
        end
        else if packetsRead < -2 then
        begin
            TLogCore.writeErrorLine(Flogger, Format('ERROR: TG_ReadPackets() returned %d.', [packetsRead]));
            Break;
        end;

        updateEegConnectionState();

        if (GetTickCount64() - lastPrintTick) >= 1000 then
        begin
            printMeasurementSnapshot();
            lastPrintTick := GetTickCount64();
        end;

        if Flogger <> nil then
            Flogger.flush;

        if packetsRead = -2 then
            Sleep(1);
    end;
end;

{*******************************************************************************
* run
*******************************************************************************}
procedure TBodyMonitorCore.stop();
begin
    FstopRequested := True;
end;

function TBodyMonitorCore.run(const aComPortName: AnsiString): Integer;
var
    errCode: Integer;
    dllVersion: Integer;
    dataLogName: AnsiString;
    streamLogName: AnsiString;
begin
    Result := 0;
    FstopRequested := False;
    FconnectedPort := '';
    resetEegFreshnessState();

    dataLogName := AnsiString('dataLog.txt');
    streamLogName := AnsiString('streamLog.txt');

    dllVersion := TG_GetVersion();
    if Flogger <> nil then
    begin
        Flogger.pushLine('{' + jsonLogTimestamp('br') +
            ',"event":"eeg_init"' +
            ',"source":"eeg"' +
            ',"level":"info"' +
            ',"stage":"sdk_version"' +
            ',"version":' + IntToStr(dllVersion) +
            ',"message":"Stream SDK for PC version"}');
        Flogger.flush;
    end;
    TLogCore.writeConsoleLine(Flogger, Format('Stream SDK for PC version: %d', [dllVersion]));

    FconnectionId := TG_GetNewConnectionId();
    if FconnectionId < 0 then
    begin
        TLogCore.writeErrorLine(Flogger, Format('ERROR: TG_GetNewConnectionId() returned %d.', [FconnectionId]));
        Result := 1;
        Exit;
    end;

    errCode := TG_SetStreamLog(FconnectionId, PAnsiChar(streamLogName));
    if errCode < 0 then
    begin
        TLogCore.writeErrorLine(Flogger, Format('ERROR: TG_SetStreamLog() returned %d.', [errCode]));
        Result := 1;
        Exit;
    end;

    errCode := TG_SetDataLog(FconnectionId, PAnsiChar(dataLogName));
    if errCode < 0 then
    begin
        TLogCore.writeErrorLine(Flogger, Format('ERROR: TG_SetDataLog() returned %d.', [errCode]));
        Result := 1;
        Exit;
    end;

    tryConnectUntilSuccess(aComPortName);

    if initializeAlgoSdk() = False then
    begin
        Result := 1;
        Exit;
    end;

    gAlgoLogger := Flogger;
    try
        runContinuousRead();
    finally
        gAlgoLogger := nil;
    end;
end;

end.

