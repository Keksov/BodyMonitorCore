unit HeartRateReader;

{$mode objfpc}{$H+}

interface

uses
    SysUtils,
    Windows,
    SimpleBle,
    LogCore,
    BreathPhaseDetector,
    BleHelper,
    BleLogHelper,
    JsonLogWriter;

const
    HR_CHAR_UUID     = '00002a37-0000-1000-8000-00805f9b34fb';
    BLE_SCAN_TIMEOUT = 10000;

type
    {***************************************************************************
     * THeartRateReader
     ***************************************************************************}
    THeartRateReader = class
private
    FbreathOnlyOutput       : Boolean;
    FbreathDetectionEnabled : Boolean;
    FbreathLock             : TRTLCriticalSection;
    FbreathMaxRrMs          : Double;
    FbreathMinDeltaMs       : Double;
    FbreathDetector         : TBreathPhaseDetector;
    Flogger                 : TLogCore;
    FstateLock              : TRTLCriticalSection;
    Fadapter                : TSimpleBleAdapter;
    Fperipheral             : TSimpleBlePeripheral;
    FhrServiceUuid          : TSimpleBleUuid;
    FhrCharUuid             : TSimpleBleUuid;
    FecgDeviceFilter        : string;
    FdeviceMac              : string;
    FdeviceIdentifier       : string;
    FfullScan               : Boolean;
    FpreScanned             : Boolean;
    Fconnected              : Boolean;
    FbleLoaded              : Boolean;
    FstopRequested          : Boolean;
    FdisconnectLogged       : Boolean;

private
    procedure   capturePeripheralIdentity();
    procedure   registerDisconnectCallback();
    procedure   reportPeripheralDisconnected();
    function    scanForHrDevice(): Boolean;
    function    ensurePeripheralConnected(): Boolean;
    function    fallbackToFreshScan(): Boolean;
    function    subscribeHeartRate(): Boolean;
    procedure   runContinuousRead();
    procedure   cleanupBle();

public
    constructor Create();
    destructor  Destroy(); override;

    function    run(const aDeviceFilter: string): Integer;
    procedure   stop();
    procedure   updateBreathSettings(aEnabled: Boolean;
        aMinDeltaMs: Double; aMaxRrMs: Double;
        aResetDetector: Boolean = True);

    property Logger: TLogCore read Flogger write Flogger;
    property BreathOnlyOutput: Boolean read FbreathOnlyOutput write FbreathOnlyOutput;
    property BreathDetectionEnabled: Boolean read FbreathDetectionEnabled write FbreathDetectionEnabled;
    property BreathMinDeltaMs: Double read FbreathMinDeltaMs write FbreathMinDeltaMs;
    property BreathMaxRrMs: Double read FbreathMaxRrMs write FbreathMaxRrMs;
    property FullScan: Boolean read FfullScan write FfullScan;

    procedure   setPreScannedPeripheral(aPeripheral: TSimpleBlePeripheral;
        aBleLibraryLoaded: Boolean; aConnected: Boolean);
    end;

function    makeSimpleBleUuid(const aUuidStr: string): TSimpleBleUuid;

implementation

uses
    DeviceScanner;

{*******************************************************************************
* heartRateDisconnectedCallback
*******************************************************************************}
procedure heartRateDisconnectedCallback(aPeripheral: TSimpleBlePeripheral;
    aUserData: PPointer);
var
    reader: THeartRateReader;
begin
    reader := nil;
    if aUserData <> nil then
        reader := THeartRateReader(Pointer(aUserData));

    if reader <> nil then
        reader.reportPeripheralDisconnected();
end;

{*******************************************************************************
* heartRateNotifyCallback
*******************************************************************************}
procedure heartRateNotifyCallback(aService: TSimpleBleUuid; aCharacteristic: TSimpleBleUuid; aData: PByte; aDataLength: NativeUInt; aUserData: PPointer);
var
    eventJson: string;
    rrMs: Double;
    flags: Byte;
    rrRaw: UInt16;
    offset: Integer;
    rrText: string;
    rrJson: string;
    hrValue: Integer;
    eventInfo: TBreathPhaseEvent;
    phaseDetected: Boolean;
    currentTimestamp: string;
    reader: THeartRateReader;
begin
    if (aData = nil) or (aDataLength < 2) then
        Exit;

    reader := nil;
    if aUserData <> nil then
        reader := THeartRateReader(Pointer(aUserData));

    flags := aData[0];
    offset := 1;

    // Bit 0: HR value format (0 = UINT8, 1 = UINT16)
    if (flags and $01) = 0 then
    begin
        hrValue := aData[offset];
        Inc(offset);
    end
    else
    begin
        if aDataLength < 3 then
            Exit;
        hrValue := aData[offset] or (aData[offset + 1] shl 8);
        Inc(offset, 2);
    end;

    // Bit 3: Energy Expended present — skip 2 bytes
    if (flags and $08) <> 0 then
        Inc(offset, 2);

    currentTimestamp := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now());

    // Bit 4: RR-Interval values present
    rrText := '';
    rrJson := '';
    if (flags and $10) <> 0 then
    begin
        while (offset + 1) < Integer(aDataLength) do
        begin
            rrRaw := UInt16(aData[offset]) or (UInt16(aData[offset + 1]) shl 8);
            rrMs := rrRaw * 1000.0 / 1024.0;

            phaseDetected := False;
            if reader <> nil then
            begin
                EnterCriticalSection(reader.FbreathLock);
                try
                    if reader.FbreathDetectionEnabled and
                        (reader.FbreathDetector <> nil) then
                        phaseDetected := reader.FbreathDetector.addSample(hrValue,
                            rrMs, eventInfo);
                finally
                    LeaveCriticalSection(reader.FbreathLock);
                end;
            end;

            if phaseDetected then
            begin
                if reader.Flogger <> nil then
                begin
                    eventJson := '{' + jsonLogTimestamp('br') +
                        ',"event":"breath_phase"' +
                        ',"phase":"' + breathPhaseToText(eventInfo.Phase) + '"' +
                        ',"extremum":"' + breathExtremumToText(eventInfo.Phase) + '"' +
                        ',"hr":' + IntToStr(eventInfo.HrValue) +
                        ',"rr_raw_ms":' + jsonLogFloat3(eventInfo.RawRrMs) +
                        ',"rr_smooth_ms":' + jsonLogFloat3(eventInfo.SmoothRrMs) +
                        ',"delta_ms":' + jsonLogFloat3(eventInfo.DeltaMs) +
                        ',"sample_index":' + IntToStr(eventInfo.SampleIndex) + '}';
                    reader.Flogger.pushLine(eventJson);
                end;

                TLogCore.writeConsoleLine(reader.Flogger,
                    Format('%s: breath_phase=%s extremum=%s hr=%d rr_raw_ms=%s rr_smooth_ms=%s delta_ms=%s',
                        [currentTimestamp,
                         breathPhaseToText(eventInfo.Phase),
                         breathExtremumToText(eventInfo.Phase),
                         eventInfo.HrValue,
                         jsonLogFloat3(eventInfo.RawRrMs),
                         jsonLogFloat3(eventInfo.SmoothRrMs),
                         jsonLogFloat3(eventInfo.DeltaMs)]));
            end;

            if rrText <> '' then
            begin
                rrText := rrText + ',';
                rrJson := rrJson + ',';
            end;
            rrText := rrText + FormatFloat('0', rrMs);
            rrJson := rrJson + jsonLogFloat3(rrMs);
            Inc(offset, 2);
        end;
    end;

    if (reader <> nil) and (reader.Flogger <> nil) then
    begin
        reader.Flogger.pushLine(
            '{' + jsonLogTimestamp('br') +
            ',"event":"hr_notification"' +
            ',"hr":' + IntToStr(hrValue) +
            ',"rr":[' + rrJson + ']}');
    end;

    if (reader <> nil) and reader.FbreathOnlyOutput then
        Exit;

    if reader <> nil then
        TLogCore.writeConsoleLine(reader.Flogger,
            Format('%s: hr=%d rr=%s', [currentTimestamp, hrValue, rrText]))
    else
        TLogCore.writeConsoleLine(nil,
            Format('%s: hr=%d rr=%s', [currentTimestamp, hrValue, rrText]));
end;

{*******************************************************************************
* makeSimpleBleUuid
*******************************************************************************}
function makeSimpleBleUuid(const aUuidStr: string): TSimpleBleUuid;
var
    i: Integer;
begin
    FillChar(Result, SizeOf(Result), 0);
    for i := 1 to Length(aUuidStr) do
    begin
        if i > SIMPLEBLE_UUID_STR_LEN - 1 then
            Break;
        Result.Value[i - 1] := aUuidStr[i];
    end;
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor THeartRateReader.Create();
begin
    inherited Create;
    FbreathOnlyOutput := False;
    FbreathDetectionEnabled := False;
    InitCriticalSection(FbreathLock);
    InitCriticalSection(FstateLock);
    FbreathMinDeltaMs := 3.0;
    FbreathMaxRrMs := 1300.0;
    FbreathDetector := TBreathPhaseDetector.Create;
    Flogger := nil;
    Fadapter := 0;
    Fperipheral := 0;
    FhrServiceUuid := makeSimpleBleUuid(HR_SERVICE_UUID);
    FhrCharUuid := makeSimpleBleUuid(HR_CHAR_UUID);
    FecgDeviceFilter := '';
    FdeviceMac := '';
    FdeviceIdentifier := '';
    FfullScan := False;
    FpreScanned := False;
    Fconnected := False;
    FbleLoaded := False;
    FstopRequested := False;
    FdisconnectLogged := False;
end;

{*******************************************************************************
* Destroy
*******************************************************************************}
destructor THeartRateReader.Destroy();
begin
    cleanupBle();
    FreeAndNil(FbreathDetector);
    DoneCriticalSection(FstateLock);
    DoneCriticalSection(FbreathLock);
    inherited Destroy;
end;

{*******************************************************************************
* capturePeripheralIdentity
*******************************************************************************}
procedure THeartRateReader.capturePeripheralIdentity();
var
    macPtr: PChar;
    idPtr: PChar;
    macText: string;
    idText: string;
begin
    macText := '';
    idText := '';

    if Fperipheral <> 0 then
    begin
        macPtr := SimpleBlePeripheralAddress(Fperipheral);
        idPtr := SimpleBlePeripheralIdentifier(Fperipheral);

        if macPtr <> nil then
            macText := string(macPtr);
        if idPtr <> nil then
            idText := string(idPtr);
    end;

    EnterCriticalSection(FstateLock);
    try
        FdeviceMac := macText;
        FdeviceIdentifier := idText;
    finally
        LeaveCriticalSection(FstateLock);
    end;
end;

{*******************************************************************************
* registerDisconnectCallback
*******************************************************************************}
procedure THeartRateReader.registerDisconnectCallback();
begin
    if Fperipheral = 0 then
        Exit;

    SimpleBlePeripheralSetCallbackOnDisconnected(Fperipheral,
        @heartRateDisconnectedCallback, PPointer(Self));
end;

{*******************************************************************************
* reportPeripheralDisconnected
*******************************************************************************}
procedure THeartRateReader.reportPeripheralDisconnected();
var
    msg: string;
    line: string;
    mac: string;
    idText: string;
begin
    msg := 'BLE Heart Rate device disconnected.';

    EnterCriticalSection(FstateLock);
    try
        if FdisconnectLogged then
            Exit;

        Fconnected := False;
        FdisconnectLogged := True;
        mac := FdeviceMac;
        idText := FdeviceIdentifier;
    finally
        LeaveCriticalSection(FstateLock);
    end;

    if (idText <> '') and (mac <> '') then
        msg := Format('BLE Heart Rate device disconnected: %s [%s].',
            [idText, mac])
    else if idText <> '' then
        msg := Format('BLE Heart Rate device disconnected: %s.', [idText])
    else if mac <> '' then
        msg := Format('BLE Heart Rate device disconnected: [%s].', [mac]);

    if Flogger <> nil then
    begin
        line := '{' + jsonLogTimestamp('br') +
            ',"event":"ble_connection"' +
            ',"source":"ecg"' +
            ',"level":"warn"' +
            ',"state":"offline"';

        if mac <> '' then
            line := line + ',"mac":"' + jsonEscape(mac) + '"';
        if idText <> '' then
            line := line + ',"identifier":"' + jsonEscape(idText) + '"';

        line := line + ',"message":"' + jsonEscape(msg) + '"}';
        Flogger.pushLine(line);
    end;

    TLogCore.writeConsoleLine(Flogger, msg);
end;

{*******************************************************************************
* updateBreathSettings
*******************************************************************************}
procedure THeartRateReader.updateBreathSettings(aEnabled: Boolean;
    aMinDeltaMs: Double; aMaxRrMs: Double; aResetDetector: Boolean = True);
begin
    EnterCriticalSection(FbreathLock);
    try
        FbreathDetectionEnabled := aEnabled;
        FbreathMinDeltaMs := aMinDeltaMs;
        FbreathMaxRrMs := aMaxRrMs;

        if FbreathDetector <> nil then
        begin
            FbreathDetector.MinDeltaMs := FbreathMinDeltaMs;
            FbreathDetector.MaxValidRrMs := FbreathMaxRrMs;
            if aResetDetector then
                FbreathDetector.reset();
        end;
    finally
        LeaveCriticalSection(FbreathLock);
    end;
end;

{*******************************************************************************
* setPreScannedPeripheral
*******************************************************************************}
procedure THeartRateReader.setPreScannedPeripheral(
    aPeripheral: TSimpleBlePeripheral; aBleLibraryLoaded: Boolean;
    aConnected: Boolean);
begin
    Fperipheral := aPeripheral;
    FbleLoaded := aBleLibraryLoaded;
    FpreScanned := aPeripheral <> 0;

    EnterCriticalSection(FstateLock);
    try
        Fconnected := (aPeripheral <> 0) and aConnected;
        FdisconnectLogged := False;
    finally
        LeaveCriticalSection(FstateLock);
    end;

    capturePeripheralIdentity();
end;

{*******************************************************************************
* scanForHrDevice
*******************************************************************************}
function THeartRateReader.scanForHrDevice(): Boolean;
begin
    Result := False;

    if Fperipheral = 0 then
        Exit(fallbackToFreshScan());

    if ensurePeripheralConnected() then
        Exit(True);

    writeBleScanLine(Flogger, 'connect_attempt', 'info',
        'Cached Heart Rate device reconnect failed. Falling back to fresh BLE scan.');
    cleanupBle();
    Result := fallbackToFreshScan();
end;

{*******************************************************************************
* ensurePeripheralConnected
*******************************************************************************}
function THeartRateReader.ensurePeripheralConnected(): Boolean;
begin
    Result := Fperipheral <> 0;
    if not Result then
        Exit;

    EnterCriticalSection(FstateLock);
    try
        Result := Fconnected;
    finally
        LeaveCriticalSection(FstateLock);
    end;

    if Result then
        Exit(True);

    writeBleScanLine(Flogger, 'connect_attempt', 'info',
        'Connecting to cached Heart Rate device...');

    Result := SimpleBlePeripheralConnect(Fperipheral) = SIMPLEBLE_SUCCESS;
    if Result then
    begin
        EnterCriticalSection(FstateLock);
        try
            Fconnected := True;
            FdisconnectLogged := False;
        finally
            LeaveCriticalSection(FstateLock);
        end;

        capturePeripheralIdentity();
    end
    else
        writeBleScanLine(Flogger, 'connect_attempt', 'error',
            'ERROR: Failed to connect to cached Heart Rate device.');
end;

{*******************************************************************************
* fallbackToFreshScan
*******************************************************************************}
function THeartRateReader.fallbackToFreshScan(): Boolean;
var
    msg: string;
    filters: TScanFilterArray;
    scanner: TDeviceScanner;
    scanResult: TDeviceScanResult;
    filterText: string;
    isAddressFilter: Boolean;
begin
    Result := False;
    filterText := Trim(FecgDeviceFilter);
    isAddressFilter := Pos(':', filterText) > 0;

    SetLength(filters, 1);
    filters[0].Kind := sfHeartRateService;
    filters[0].Value := '';

    if filterText <> '' then
    begin
        if isAddressFilter then
        begin
            writeBleScanLine(Flogger, 'filter', 'info',
                Format('ECG address filter active: exact match "%s".',
                    [filterText]));
            SetLength(filters, 2);
            filters[1].Kind := sfAddress;
            filters[1].Value := filterText;
        end
        else
        begin
            writeBleScanLine(Flogger, 'filter', 'info',
                Format('ECG name filter active: contains "%s" (case-insensitive).',
                    [filterText]));
            SetLength(filters, 2);
            filters[1].Kind := sfName;
            filters[1].Value := filterText;
        end;
    end;

    scanner := TDeviceScanner.Create(Flogger);
    try
        if not scanner.scan(filters, FfullScan, True, False, scanResult) then
            Exit;

        if scanResult.FirstMatchedPeripheral = 0 then
        begin
            writeBleScanLine(Flogger, 'scan_results', 'error',
                'ERROR: No Heart Rate device found.');
            Exit;
        end;

        msg := Format('Found Heart Rate device: %s [%s]', [
            scanResult.FirstMatchedIdentifier,
            scanResult.FirstMatchedMac]);
        writeBleScanLine(Flogger, 'device_found', 'info', msg);

        Fperipheral := scanResult.FirstMatchedPeripheral;
        FbleLoaded := scanResult.BleLibraryLoaded;
        FpreScanned := True;
        Fconnected := False;

        if not ensurePeripheralConnected() then
        begin
            cleanupBle();
            Exit;
        end;

        Result := True;
    finally
        FreeAndNil(scanner);
    end;
end;

{*******************************************************************************
* subscribeHeartRate
*******************************************************************************}
function THeartRateReader.subscribeHeartRate(): Boolean;
var
    i, j: Integer;
    service: TSimpleBleService;
    svcCount: NativeUInt;
begin
    Result := False;
    registerDisconnectCallback();
    svcCount := SimpleBlePeripheralServicesCount(Fperipheral);

    for i := 0 to svcCount - 1 do
    begin
        if SimpleBlePeripheralServicesGet(Fperipheral, i, service) <> SIMPLEBLE_SUCCESS then
            Continue;

        if LowerCase(uuidToString(service.Uuid)) <> HR_SERVICE_UUID then
            Continue;

        for j := 0 to service.CharacteristicCount - 1 do
        begin
            if LowerCase(uuidToString(service.Characteristics[j].Uuid)) = HR_CHAR_UUID then
            begin
                if SimpleBlePeripheralNotify(Fperipheral, service.Uuid, service.Characteristics[j].Uuid, @heartRateNotifyCallback, PPointer(Self)) = SIMPLEBLE_SUCCESS then
                begin
                    writeBleScanLine(Flogger, 'subscribe', 'info',
                        'Subscribed to Heart Rate notifications.');
                    Result := True;
                    Exit;
                end
                else
                begin
                    writeBleScanLine(Flogger, 'subscribe', 'error',
                        'ERROR: Failed to subscribe to Heart Rate notifications.');
                    Exit;
                end;
            end;
        end;
    end;

    writeBleScanLine(Flogger, 'subscribe', 'error',
        'ERROR: Heart Rate Measurement characteristic not found.');
end;

{*******************************************************************************
* runContinuousRead
* NOTE: cleanupBle() must only be called after runContinuousRead() returns
*       (i.e. after FstopRequested becomes True), because the polling loop
*       accesses Fperipheral without holding FstateLock.
*******************************************************************************}
procedure THeartRateReader.runContinuousRead();
var
    err: TSimpleBleErr;
    connected: Boolean;
    shouldCheck: Boolean;
begin
    TLogCore.writeConsoleLine(Flogger, 'Reading heart rate data... Press Ctrl+C to stop.');
    while not FstopRequested do
    begin
        shouldCheck := False;
        if Fperipheral <> 0 then
        begin
            EnterCriticalSection(FstateLock);
            try
                shouldCheck := Fconnected;
            finally
                LeaveCriticalSection(FstateLock);
            end;

            if shouldCheck then
            begin
                connected := False;
                err := SimpleBlePeripheralIsConnected(Fperipheral, connected);
                if (err <> SIMPLEBLE_SUCCESS) or (connected = False) then
                    reportPeripheralDisconnected();
            end;
        end;

        if Flogger <> nil then
            Flogger.flush;
        Sleep(100);
    end;
end;

{*******************************************************************************
* cleanupBle
*******************************************************************************}
procedure THeartRateReader.stop();
begin
    FstopRequested := True;
end;

procedure THeartRateReader.cleanupBle();
var
    connected: Boolean;
begin
    if Fperipheral <> 0 then
    begin
        EnterCriticalSection(FstateLock);
        try
            connected := Fconnected;
            Fconnected := False;
            FdisconnectLogged := False;
        finally
            LeaveCriticalSection(FstateLock);
        end;

        if connected then
        begin
            SimpleBlePeripheralUnsubscribe(Fperipheral, FhrServiceUuid,
                FhrCharUuid);
            SimpleBlePeripheralDisconnect(Fperipheral);
        end;

        SimpleBlePeripheralReleaseHandle(Fperipheral);
        Fperipheral := 0;
        FpreScanned := False;
        capturePeripheralIdentity();
    end;

    if Fadapter <> 0 then
    begin
        SimpleBleAdapterReleaseHandle(Fadapter);
        Fadapter := 0;
    end;

    if FbleLoaded then
    begin
        SimpleBleUnloadLibrary();
        FbleLoaded := False;
    end;
end;

function THeartRateReader.run(const aDeviceFilter: string): Integer;
begin
    Result := 0;
    FecgDeviceFilter := aDeviceFilter;
    updateBreathSettings(FbreathDetectionEnabled, FbreathMinDeltaMs,
        FbreathMaxRrMs);

    if not scanForHrDevice() then
    begin
        Result := 1;
        Exit;
    end;

    if not subscribeHeartRate() then
    begin
        Result := 1;
        Exit;
    end;

    runContinuousRead();
end;

end.
