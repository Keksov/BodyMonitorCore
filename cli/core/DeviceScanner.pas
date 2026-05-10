unit DeviceScanner;

{$mode objfpc}{$H+}

interface

uses
    SysUtils,
    Classes,
    Windows,
    SimpleCBle,
    LogCore,
    BleHelper,
    BleLogHelper,
    BleComPortFinder;

const
    SCAN_TIMEOUT_MS    = 10000;
    CONNECT_TIMEOUT_MS = 10000;

type
    PScanAddressMatchContext = ^TScanAddressMatchContext;
    TScanAddressMatchContext = record
        TargetAddress: string;
        MatchFound: LongInt;
    end;

    TScanFilterKind = (
        sfHeartRateService,
        sfAddress,
        sfName
    );

    TScanFilter = record
        Kind: TScanFilterKind;
        Value: string;
    end;

    TScanFilterArray = array of TScanFilter;

    TScannedDevice = record
        Index: Integer;
        Mac: string;
        Identifier: string;
        DeviceType: string;
        ComPort: string;
        Peripheral: TSimpleBlePeripheral;
        Connectable: Boolean;
        Connected: Boolean;
        MatchesFilters: Boolean;
        HasHeartRate: Boolean;
    end;

    TScannedDeviceArray = array of TScannedDevice;

    TDeviceScanResult = record
        Devices: TScannedDeviceArray;
        FoundCount: Integer;
        MatchedCount: Integer;
        ConnectedCount: Integer;
        ConnectFailCount: Integer;
        NotConnectableCount: Integer;
        SkippedByFilterCount: Integer;
        FirstMatchedPeripheral: TSimpleBlePeripheral;
        FirstMatchedMac: string;
        FirstMatchedIdentifier: string;
        BleLibraryLoaded: Boolean;
    end;

    TBleConnectThread = class(TThread)
    private
        Fperipheral             : TSimpleBlePeripheral;
        Fsuccess                : Boolean;

    protected
        procedure   Execute(); override;

    public
        constructor Create(aPeripheral: TSimpleBlePeripheral);

        property Success: Boolean read Fsuccess;
    end;

    TDeviceScanner = class
    private
        Flogger                 : TLogCore;
        FscanAdapter            : TSimpleBleAdapter;
        FcancelFlag             : PLongInt;
        FscanLock               : TRTLCriticalSection;

    private
        function    isCancelRequested(): Boolean;
        procedure   writeScanCancelled();
        function    findExactAddressFilter(const aFilters: TScanFilterArray;
            out aAddress: string): Boolean;
        function    passesPreConnectFilters(const aFilters: TScanFilterArray;
            const aDevice: TScannedDevice): Boolean;
        function    scanUntilAddressFound(aAdapter: TSimpleBleAdapter;
            const aAddress: string; aTimeoutMs: DWORD;
            out aCancelled: Boolean): TSimpleBleErr;
        function    gattServiceNameByUuid(const aUuid: string): string;
        function    findComPortForMac(const aBleAddress: string;
            const aDevices: TSerialDeviceInfoArray): string;
        function    tryConnectPeripheral(aPeripheral: TSimpleBlePeripheral;
            aTimeoutMs: DWORD): Boolean;
        function    classifyDeviceByServices(aPeripheral: TSimpleBlePeripheral): string;
        function    peripheralHasHrService(aPeripheral: TSimpleBlePeripheral): Boolean;
        function    deviceMatchesFilters(const aFilters: TScanFilterArray;
            const aDevice: TScannedDevice): Boolean;
        procedure   appendDevice(var aDevices: TScannedDeviceArray;
            const aDevice: TScannedDevice);

    public
        constructor Create(aLogger: TLogCore);
        destructor  Destroy(); override;

        procedure   setCancelFlag(aCancelFlag: PLongInt);
        procedure   requestCancel();

        function    pingAddress(const aAddress: string;
            out aIdentifier: string): Boolean;

        function    discover(aRetainPeripheralHandles: Boolean;
            out aResult: TDeviceScanResult): Boolean;

        function    scan(const aFilters: TScanFilterArray;
            aFullScan: Boolean;
            aKeepFirstMatchedConnected: Boolean;
            aRetainPeripheralHandles: Boolean;
            out aResult: TDeviceScanResult): Boolean;
    end;

implementation

procedure scanAddressNoopCallback(aAdapter: TSimpleBleAdapter;
    aPeripheral: TSimpleBlePeripheral; aUserData: Pointer); cdecl;
begin
end;

procedure scanAddressMatchCallback(aAdapter: TSimpleBleAdapter;
    aPeripheral: TSimpleBlePeripheral; aUserData: Pointer); cdecl;
var
    address: PChar;
    context: PScanAddressMatchContext;
begin
    if (aPeripheral = 0) or (aUserData = nil) then
        Exit;

    context := PScanAddressMatchContext(aUserData);
    if InterlockedCompareExchange(context^.MatchFound, 0, 0) <> 0 then
        Exit;

    address := SimpleBlePeripheralAddress(aPeripheral);
    if address = nil then
        Exit;

    try
        if LowerCase(Trim(string(address))) = context^.TargetAddress then
            InterlockedExchange(context^.MatchFound, 1);
    finally
        SimpleBleFree(address);
    end;
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor TBleConnectThread.Create(aPeripheral: TSimpleBlePeripheral);
begin
    inherited Create(True);
    FreeOnTerminate := False;
    Fperipheral := aPeripheral;
    Fsuccess := False;
end;

{*******************************************************************************
* Execute
*******************************************************************************}
procedure TBleConnectThread.Execute();
begin
    Fsuccess := SimpleBlePeripheralConnect(Fperipheral) = SIMPLEBLE_SUCCESS;
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor TDeviceScanner.Create(aLogger: TLogCore);
begin
    inherited Create;
    Flogger := aLogger;
    FscanAdapter := 0;
    FcancelFlag := nil;
    InitCriticalSection(FscanLock);
end;

{*******************************************************************************
* Destroy
*******************************************************************************}
destructor TDeviceScanner.Destroy();
begin
    DoneCriticalSection(FscanLock);
    inherited Destroy;
end;

{*******************************************************************************
* setCancelFlag
*******************************************************************************}
procedure TDeviceScanner.setCancelFlag(aCancelFlag: PLongInt);
begin
    FcancelFlag := aCancelFlag;
    if FcancelFlag <> nil then
        InterlockedExchange(FcancelFlag^, 0);
end;

{*******************************************************************************
* requestCancel
*******************************************************************************}
procedure TDeviceScanner.requestCancel();
begin
    if FcancelFlag <> nil then
        InterlockedExchange(FcancelFlag^, 1);

    EnterCriticalSection(FscanLock);
    try
        if FscanAdapter <> 0 then
            SimpleBleAdapterScanStop(FscanAdapter);
    finally
        LeaveCriticalSection(FscanLock);
    end;
end;

{*******************************************************************************
* pingAddress
*******************************************************************************}
function TDeviceScanner.pingAddress(const aAddress: string;
    out aIdentifier: string): Boolean;
var
    i: Integer;
    scanErr: TSimpleBleErr;
    errMsg: string;
    targetAddress: string;
    scanCancelled: Boolean;
    adapter: TSimpleBleAdapter;
    addrStr: string;
    bleReady: Boolean;
    identStr: string;
    scanCount: NativeUInt;
    address: PChar;
    identifier: PChar;
    peripheral: TSimpleBlePeripheral;
begin
    aIdentifier := '';
    Result := False;
    adapter := 0;
    bleReady := False;
    scanCancelled := False;
    targetAddress := LowerCase(Trim(aAddress));

    if targetAddress = '' then
    begin
        writeBleScanLine(Flogger, 'ping_start', 'error',
            'ERROR: Empty ping target address.');
        Exit;
    end;

    if not initBleAdapter(adapter, errMsg) then
    begin
        writeBleScanLine(Flogger, 'init', 'error', 'ERROR: ' + errMsg);
        SimpleBleUnloadLibrary();
        Exit;
    end;
    bleReady := True;

    EnterCriticalSection(FscanLock);
    try
        FscanAdapter := adapter;
    finally
        LeaveCriticalSection(FscanLock);
    end;

    try
        if isCancelRequested() then
        begin
            writeScanCancelled();
            Exit;
        end;

        writeBleScanLine(Flogger, 'ping_start', 'info',
            Format('Pinging BLE device [%s]...', [targetAddress]));

        scanErr := scanUntilAddressFound(adapter, targetAddress,
            SCAN_TIMEOUT_MS, scanCancelled);
        if scanErr <> SIMPLEBLE_SUCCESS then
        begin
            if isCancelRequested() or scanCancelled then
                writeScanCancelled()
            else
                writeBleScanLine(Flogger, 'ping_start', 'error',
                    'ERROR: BLE ping scan failed.');
            Exit;
        end;

        scanCount := SimpleBleAdapterScanGetResultsCount(adapter);
        for i := 0 to scanCount - 1 do
        begin
            peripheral := SimpleBleAdapterScanGetResultsHandle(adapter, i);
            identifier := SimpleBlePeripheralIdentifier(peripheral);
            address := SimpleBlePeripheralAddress(peripheral);

            if identifier <> nil then
                identStr := string(identifier)
            else
                identStr := '';

            if address <> nil then
                addrStr := LowerCase(Trim(string(address)))
            else
                addrStr := '';

            if identifier <> nil then
                SimpleBleFree(identifier);
            if address <> nil then
                SimpleBleFree(address);

            if addrStr = targetAddress then
            begin
                aIdentifier := identStr;
                Result := True;
                SimpleBlePeripheralReleaseHandle(peripheral);
                Break;
            end;

            SimpleBlePeripheralReleaseHandle(peripheral);
        end;

        if Result then
            writeBleScanLine(Flogger, 'ping_results', 'info',
                Format('Device reachable: %s [%s]', [aIdentifier, targetAddress]))
        else
            writeBleScanLine(Flogger, 'ping_results', 'error',
                Format('ERROR: Could not find device [%s].', [targetAddress]));
    finally
        EnterCriticalSection(FscanLock);
        try
            FscanAdapter := 0;
            if adapter <> 0 then
            begin
                SimpleBleAdapterReleaseHandle(adapter);
                adapter := 0;
            end;
        finally
            LeaveCriticalSection(FscanLock);
        end;

        if bleReady then
            SimpleBleUnloadLibrary();
    end;
end;

{*******************************************************************************
* discover
*******************************************************************************}
function TDeviceScanner.discover(aRetainPeripheralHandles: Boolean;
    out aResult: TDeviceScanResult): Boolean;
var
    i: Integer;
    scanErr: TSimpleBleErr;
    errMsg: string;
    paired: Boolean;
    scanCancelled: Boolean;
    adapter: TSimpleBleAdapter;
    addrStr: string;
    address: PChar;
    bleReady: Boolean;
    identStr: string;
    scanCount: NativeUInt;
    identifier: PChar;
    peripheral: TSimpleBlePeripheral;
    wmiDevices: TSerialDeviceInfoArray;
    connectable: Boolean;
    currentDevice: TScannedDevice;
    hasRetainedHandles: Boolean;
begin
    FillChar(aResult, SizeOf(aResult), 0);
    SetLength(aResult.Devices, 0);
    aResult.FirstMatchedPeripheral := 0;
    aResult.FirstMatchedMac := '';
    aResult.FirstMatchedIdentifier := '';
    aResult.BleLibraryLoaded := False;
    adapter := 0;
    bleReady := False;
    hasRetainedHandles := False;
    scanCancelled := False;
    Result := False;

    TBleComPortFinder.listAllSerialDevices(wmiDevices);

    if not initBleAdapter(adapter, errMsg) then
    begin
        writeBleScanLine(Flogger, 'init', 'error', 'ERROR: ' + errMsg);
        SimpleBleUnloadLibrary();
        Exit;
    end;
    bleReady := True;

    EnterCriticalSection(FscanLock);
    try
        FscanAdapter := adapter;
    finally
        LeaveCriticalSection(FscanLock);
    end;

    try
        if isCancelRequested() then
        begin
            writeScanCancelled();
            Exit;
        end;

        writeBleScanLine(Flogger, 'init', 'info',
            Format('SimpleBLE version: %s', [string(SimpleBleGetVersion())]));

        writeBleScanLine(Flogger, 'scan_start', 'info',
            Format('Scanning for BLE devices (%d seconds)...', [SCAN_TIMEOUT_MS div 1000]));
        scanErr := SimpleBleAdapterScanFor(adapter, SCAN_TIMEOUT_MS);
        if scanErr <> SIMPLEBLE_SUCCESS then
        begin
            if isCancelRequested() then
                writeScanCancelled()
            else
                writeBleScanLine(Flogger, 'scan_start', 'error',
                    'ERROR: BLE scan failed.');
            Exit;
        end;

        scanCount := SimpleBleAdapterScanGetResultsCount(adapter);
        writeBleScanCountLine(Flogger, 'scan_results', 'info',
            Format('Found %d BLE device(s).', [scanCount]), scanCount);

        for i := 0 to scanCount - 1 do
        begin
            if isCancelRequested() then
            begin
                scanCancelled := True;
                Break;
            end;

            Inc(aResult.FoundCount);
            peripheral := SimpleBleAdapterScanGetResultsHandle(adapter, i);
            identifier := SimpleBlePeripheralIdentifier(peripheral);
            address := SimpleBlePeripheralAddress(peripheral);

            if identifier <> nil then
                identStr := string(identifier)
            else
                identStr := '';

            if address <> nil then
                addrStr := string(address)
            else
                addrStr := '';

            if identifier <> nil then
                SimpleBleFree(identifier);
            if address <> nil then
                SimpleBleFree(address);

            writeBleScanLine(Flogger, 'scan_results', 'info',
                Format('  [%d] %s [%s]', [i + 1, identStr, addrStr]));

            connectable := False;
            paired := False;
            SimpleBlePeripheralIsConnectable(peripheral, connectable);
            if connectable then
                SimpleBlePeripheralIsPaired(peripheral, paired);

            currentDevice.Index := i + 1;
            currentDevice.Mac := addrStr;
            currentDevice.Identifier := identStr;
            currentDevice.DeviceType := 'unknown';
            currentDevice.ComPort := findComPortForMac(addrStr, wmiDevices);
            currentDevice.Peripheral := 0;
            currentDevice.Connectable := connectable;
            currentDevice.Connected := False;
            currentDevice.MatchesFilters := True;
            currentDevice.HasHeartRate := False;

            if not connectable then
                Inc(aResult.NotConnectableCount);

            if aRetainPeripheralHandles then
            begin
                currentDevice.Peripheral := peripheral;
                hasRetainedHandles := True;
            end;

            appendDevice(aResult.Devices, currentDevice);

            if not aRetainPeripheralHandles then
                SimpleBlePeripheralReleaseHandle(peripheral);
        end;

        if scanCancelled then
        begin
            writeScanCancelled();
            Exit;
        end;

        writeBleScanCountLine(Flogger, 'scan_summary', 'info',
            Format('Processed %d scanned device(s).', [aResult.FoundCount]),
            aResult.FoundCount);

        Result := True;
    finally
        EnterCriticalSection(FscanLock);
        try
            FscanAdapter := 0;
            if adapter <> 0 then
            begin
                SimpleBleAdapterReleaseHandle(adapter);
                adapter := 0;
            end;
        finally
            LeaveCriticalSection(FscanLock);
        end;

        if bleReady then
        begin
            if aRetainPeripheralHandles and hasRetainedHandles then
                aResult.BleLibraryLoaded := True
            else
                SimpleBleUnloadLibrary();
        end;
    end;
end;

{*******************************************************************************
* isCancelRequested
*******************************************************************************}
function TDeviceScanner.isCancelRequested(): Boolean;
begin
    Result := (FcancelFlag <> nil) and
        (InterlockedCompareExchange(FcancelFlag^, 0, 0) <> 0);
end;

{*******************************************************************************
* writeScanCancelled
*******************************************************************************}
procedure TDeviceScanner.writeScanCancelled();
begin
    writeBleScanLine(Flogger, 'scan_cancelled', 'info',
        'BLE scan cancelled.');
end;

{*******************************************************************************
* findExactAddressFilter
*******************************************************************************}
function TDeviceScanner.findExactAddressFilter(const aFilters: TScanFilterArray;
    out aAddress: string): Boolean;
var
    i: Integer;
begin
    aAddress := '';
    for i := 0 to Length(aFilters) - 1 do
    begin
        if aFilters[i].Kind <> sfAddress then
            Continue;

        aAddress := LowerCase(Trim(aFilters[i].Value));
        Result := aAddress <> '';
        Exit;
    end;

    Result := False;
end;

{*******************************************************************************
* passesPreConnectFilters
*******************************************************************************}
function TDeviceScanner.passesPreConnectFilters(const aFilters: TScanFilterArray;
    const aDevice: TScannedDevice): Boolean;
var
    i: Integer;
    v: string;
begin
    Result := True;
    for i := 0 to Length(aFilters) - 1 do
    begin
        case aFilters[i].Kind of
            sfAddress:
            begin
                v := LowerCase(Trim(aFilters[i].Value));
                if (v <> '') and (LowerCase(Trim(aDevice.Mac)) <> v) then
                    Exit(False);
            end;
            sfName:
            begin
                v := LowerCase(aFilters[i].Value);
                if (v <> '') and (Pos(v, LowerCase(aDevice.Identifier)) = 0) then
                    Exit(False);
            end;
        else
            Continue;
        end;
    end;
end;

{*******************************************************************************
* scanUntilAddressFound
*******************************************************************************}
function TDeviceScanner.scanUntilAddressFound(aAdapter: TSimpleBleAdapter;
    const aAddress: string; aTimeoutMs: DWORD;
    out aCancelled: Boolean): TSimpleBleErr;
var
    active: Boolean;
    callbackErr: TSimpleBleErr;
    context: TScanAddressMatchContext;
    startedAt: QWord;
    stopWaitStartedAt: QWord;
begin
    aCancelled := False;
    context.TargetAddress := LowerCase(Trim(aAddress));
    context.MatchFound := 0;

    Result := SimpleBleAdapterSetCallbackOnScanFound(aAdapter,
        @scanAddressMatchCallback, @context);
    if Result <> SIMPLEBLE_SUCCESS then
        Exit;

    callbackErr := SimpleBleAdapterSetCallbackOnScanUpdated(aAdapter,
        @scanAddressMatchCallback, @context);
    if callbackErr <> SIMPLEBLE_SUCCESS then
    begin
        SimpleBleAdapterSetCallbackOnScanFound(aAdapter,
            @scanAddressNoopCallback, nil);
        Exit(callbackErr);
    end;

    Result := SimpleBleAdapterScanStart(aAdapter);
    if Result <> SIMPLEBLE_SUCCESS then
    begin
        SimpleBleAdapterSetCallbackOnScanUpdated(aAdapter,
            @scanAddressNoopCallback, nil);
        SimpleBleAdapterSetCallbackOnScanFound(aAdapter,
            @scanAddressNoopCallback, nil);
        Exit;
    end;

    startedAt := GetTickCount64();

    while True do
    begin
        if isCancelRequested() then
        begin
            aCancelled := True;
            SimpleBleAdapterScanStop(aAdapter);
            Exit(SIMPLEBLE_FAILURE);
        end;

        if (InterlockedCompareExchange(context.MatchFound, 0, 0) <> 0) or
            (GetTickCount64() - startedAt >= QWord(aTimeoutMs)) then
            Break;

        Sleep(50);
    end;

    Result := SimpleBleAdapterScanStop(aAdapter);
    SimpleBleAdapterSetCallbackOnScanUpdated(aAdapter,
        @scanAddressNoopCallback, nil);
    SimpleBleAdapterSetCallbackOnScanFound(aAdapter,
        @scanAddressNoopCallback, nil);
    if Result <> SIMPLEBLE_SUCCESS then
        Exit;

    active := True;
    stopWaitStartedAt := GetTickCount64();
    while active do
    begin
        if SimpleBleAdapterScanIsActive(aAdapter, active) <> SIMPLEBLE_SUCCESS then
            Break;

        if active then
        begin
            if GetTickCount64() - stopWaitStartedAt >= 5000 then
                Break;
            Sleep(25);
        end;
    end;

    Result := SIMPLEBLE_SUCCESS;
end;

{*******************************************************************************
* appendDevice
*******************************************************************************}
procedure TDeviceScanner.appendDevice(var aDevices: TScannedDeviceArray;
    const aDevice: TScannedDevice);
var
    n: Integer;
begin
    n := Length(aDevices);
    SetLength(aDevices, n + 1);
    aDevices[n] := aDevice;
end;

{*******************************************************************************
* gattServiceNameByUuid
*******************************************************************************}
function TDeviceScanner.gattServiceNameByUuid(const aUuid: string): string;
var
    i: Integer;
    u: string;
const
    gattUuids: array[0..38] of string = (
        '00001800-0000-1000-8000-00805f9b34fb',
        '00001801-0000-1000-8000-00805f9b34fb',
        '00001802-0000-1000-8000-00805f9b34fb',
        '00001803-0000-1000-8000-00805f9b34fb',
        '00001804-0000-1000-8000-00805f9b34fb',
        '00001805-0000-1000-8000-00805f9b34fb',
        '00001806-0000-1000-8000-00805f9b34fb',
        '00001807-0000-1000-8000-00805f9b34fb',
        '00001808-0000-1000-8000-00805f9b34fb',
        '00001809-0000-1000-8000-00805f9b34fb',
        '0000180a-0000-1000-8000-00805f9b34fb',
        '0000180d-0000-1000-8000-00805f9b34fb',
        '0000180e-0000-1000-8000-00805f9b34fb',
        '0000180f-0000-1000-8000-00805f9b34fb',
        '00001810-0000-1000-8000-00805f9b34fb',
        '00001811-0000-1000-8000-00805f9b34fb',
        '00001812-0000-1000-8000-00805f9b34fb',
        '00001813-0000-1000-8000-00805f9b34fb',
        '00001814-0000-1000-8000-00805f9b34fb',
        '00001815-0000-1000-8000-00805f9b34fb',
        '00001816-0000-1000-8000-00805f9b34fb',
        '00001818-0000-1000-8000-00805f9b34fb',
        '00001819-0000-1000-8000-00805f9b34fb',
        '0000181a-0000-1000-8000-00805f9b34fb',
        '0000181b-0000-1000-8000-00805f9b34fb',
        '0000181c-0000-1000-8000-00805f9b34fb',
        '0000181d-0000-1000-8000-00805f9b34fb',
        '0000181e-0000-1000-8000-00805f9b34fb',
        '0000181f-0000-1000-8000-00805f9b34fb',
        '00001820-0000-1000-8000-00805f9b34fb',
        '00001821-0000-1000-8000-00805f9b34fb',
        '00001822-0000-1000-8000-00805f9b34fb',
        '00001823-0000-1000-8000-00805f9b34fb',
        '00001824-0000-1000-8000-00805f9b34fb',
        '00001825-0000-1000-8000-00805f9b34fb',
        '00001826-0000-1000-8000-00805f9b34fb',
        '00001827-0000-1000-8000-00805f9b34fb',
        '00001828-0000-1000-8000-00805f9b34fb',
        '00001829-0000-1000-8000-00805f9b34fb'
    );
    gattNames: array[0..38] of string = (
        'Generic Access',
        'Generic Attribute',
        'Immediate Alert',
        'Link Loss',
        'Tx Power',
        'Current Time Service',
        'Reference Time Update Service',
        'Next DST Change Service',
        'Glucose',
        'Health Thermometer',
        'Device Information',
        'Heart Rate',
        'Phone Alert Status Service',
        'Battery Service',
        'Blood Pressure',
        'Alert Notification Service',
        'Human Interface Device',
        'Scan Parameters',
        'Running Speed and Cadence',
        'Automation IO',
        'Cycling Speed and Cadence',
        'Cycling Power',
        'Location and Navigation',
        'Environmental Sensing',
        'Body Composition',
        'User Data',
        'Weight Scale',
        'Bond Management Service',
        'Continuous Glucose Monitoring',
        'Internet Protocol Support Service',
        'Indoor Positioning',
        'Pulse Oximeter Service',
        'HTTP Proxy',
        'Transport Discovery',
        'Object Transfer Service',
        'Fitness Machine',
        'Mesh Provisioning Service',
        'Mesh Proxy Service',
        'Reconnection Configuration'
    );
begin
    u := LowerCase(aUuid);

    for i := 0 to High(gattUuids) do
    begin
        if u = gattUuids[i] then
            Exit(gattNames[i]);
    end;

    Result := '';
end;

{*******************************************************************************
* findComPortForMac
*******************************************************************************}
function TDeviceScanner.findComPortForMac(const aBleAddress: string;
    const aDevices: TSerialDeviceInfoArray): string;
var
    i: Integer;
    macNorm: string;
begin
    Result := '';
    macNorm := UpperCase(StringReplace(aBleAddress, ':', '', [rfReplaceAll]));
    if macNorm = '' then
        Exit;

    for i := 0 to Length(aDevices) - 1 do
    begin
        if Pos(macNorm, UpperCase(aDevices[i].PNPDeviceID)) > 0 then
        begin
            Result := aDevices[i].DeviceID;
            Exit;
        end;
    end;
end;

{*******************************************************************************
* tryConnectPeripheral
*******************************************************************************}
function TDeviceScanner.tryConnectPeripheral(aPeripheral: TSimpleBlePeripheral;
    aTimeoutMs: DWORD): Boolean;
var
    nowTick: QWord;
    thread: TBleConnectThread;
    startTick: QWord;
    waitResult: DWORD;
begin
    Result := False;
    waitResult := WAIT_TIMEOUT;
    thread := TBleConnectThread.Create(aPeripheral);
    try
        thread.Start();
        startTick := GetTickCount64();

        while True do
        begin
            if isCancelRequested() then
            begin
                waitResult := WAIT_TIMEOUT;
                Break;
            end;

            waitResult := WaitForSingleObject(thread.Handle, 100);
            if waitResult = WAIT_OBJECT_0 then
            begin
                Result := thread.Success;
                Break;
            end;

            if waitResult <> WAIT_TIMEOUT then
                Break;

            nowTick := GetTickCount64();
            if nowTick - startTick >= QWord(aTimeoutMs) then
                Break;
        end;
    finally
        if waitResult = WAIT_OBJECT_0 then
            thread.Free
        else
            thread.FreeOnTerminate := True;
    end;
end;

{*******************************************************************************
* classifyDeviceByServices
*******************************************************************************}
function TDeviceScanner.classifyDeviceByServices(aPeripheral: TSimpleBlePeripheral): string;
var
    i: Integer;
    name: string;
    uuidStr: string;
    service: TSimpleBleService;
    svcCount: NativeUInt;
begin
    Result := '';
    svcCount := SimpleBlePeripheralServicesCount(aPeripheral);

    for i := 0 to svcCount - 1 do
    begin
        if SimpleBlePeripheralServicesGet(aPeripheral, i, service) <> SIMPLEBLE_SUCCESS then
            Continue;

        uuidStr := uuidToString(service.Uuid);
        name := gattServiceNameByUuid(uuidStr);
        if name = '' then
            name := uuidStr;

        if Result <> '' then
            Result := Result + '+' + name
        else
            Result := name;
    end;

    if Result = '' then
        Result := 'UNKNOWN';
end;

{*******************************************************************************
* peripheralHasHrService
*******************************************************************************}
function TDeviceScanner.peripheralHasHrService(aPeripheral: TSimpleBlePeripheral): Boolean;
var
    i: Integer;
    service: TSimpleBleService;
    svcCount: NativeUInt;
begin
    Result := False;
    svcCount := SimpleBlePeripheralServicesCount(aPeripheral);

    for i := 0 to svcCount - 1 do
    begin
        if SimpleBlePeripheralServicesGet(aPeripheral, i, service) = SIMPLEBLE_SUCCESS then
        begin
            if LowerCase(uuidToString(service.Uuid)) = HR_SERVICE_UUID then
            begin
                Result := True;
                Exit;
            end;
        end;
    end;
end;

{*******************************************************************************
* deviceMatchesFilters
*******************************************************************************}
function TDeviceScanner.deviceMatchesFilters(const aFilters: TScanFilterArray;
    const aDevice: TScannedDevice): Boolean;
var
    i: Integer;
    v: string;
begin
    Result := True;
    for i := 0 to Length(aFilters) - 1 do
    begin
        case aFilters[i].Kind of
            sfHeartRateService:
                if not aDevice.HasHeartRate then
                    Exit(False);
            sfAddress:
            begin
                v := LowerCase(Trim(aFilters[i].Value));
                if LowerCase(Trim(aDevice.Mac)) <> v then
                    Exit(False);
            end;
            sfName:
            begin
                v := LowerCase(aFilters[i].Value);
                if Pos(v, LowerCase(aDevice.Identifier)) = 0 then
                    Exit(False);
            end;
        end;
    end;
end;

{*******************************************************************************
* scan
*******************************************************************************}
function TDeviceScanner.scan(const aFilters: TScanFilterArray;
    aFullScan: Boolean;
    aKeepFirstMatchedConnected: Boolean;
    aRetainPeripheralHandles: Boolean;
    out aResult: TDeviceScanResult): Boolean;
var
    i: Integer;
    scanErr: TSimpleBleErr;
    msg: string;
    errMsg: string;
    exactAddressFilter: string;
    paired: Boolean;
    scanCancelled: Boolean;
    adapter: TSimpleBleAdapter;
    addrStr: string;
    pairErr: TSimpleBleErr;
    address: PChar;
    bleReady: Boolean;
    identStr: string;
    scanCount: NativeUInt;
    identifier: PChar;
    peripheral: TSimpleBlePeripheral;
    wmiDevices: TSerialDeviceInfoArray;
    connectable: Boolean;
    connectedNow: Boolean;
    currentDevice: TScannedDevice;
    hasExactAddressFilter: Boolean;
    hasRetainedHandles: Boolean;
begin
    FillChar(aResult, SizeOf(aResult), 0);
    SetLength(aResult.Devices, 0);
    aResult.FirstMatchedPeripheral := 0;
    aResult.FirstMatchedMac := '';
    aResult.FirstMatchedIdentifier := '';
    aResult.BleLibraryLoaded := False;
    adapter := 0;
    bleReady := False;
    hasRetainedHandles := False;
    scanCancelled := False;
    hasExactAddressFilter := (not aFullScan) and
        findExactAddressFilter(aFilters, exactAddressFilter);
    Result := False;

    if not hasExactAddressFilter then
        TBleComPortFinder.listAllSerialDevices(wmiDevices)
    else
        SetLength(wmiDevices, 0);

    if not initBleAdapter(adapter, errMsg) then
    begin
        writeBleScanLine(Flogger, 'init', 'error', 'ERROR: ' + errMsg);
        SimpleBleUnloadLibrary();
        Exit;
    end;
    bleReady := True;

    EnterCriticalSection(FscanLock);
    try
        FscanAdapter := adapter;
    finally
        LeaveCriticalSection(FscanLock);
    end;

    try
        if isCancelRequested() then
        begin
            writeScanCancelled();
            scanCancelled := True;
            Exit;
        end;

        msg := Format('SimpleBLE version: %s', [string(SimpleBleGetVersion())]);
        writeBleScanLine(Flogger, 'init', 'info', msg);

        writeBleScanLine(Flogger, 'scan_start', 'info',
            Format('Scanning for BLE devices (%d seconds)...', [SCAN_TIMEOUT_MS div 1000]));
        if hasExactAddressFilter then
            scanErr := scanUntilAddressFound(adapter, exactAddressFilter,
                SCAN_TIMEOUT_MS, scanCancelled)
        else
            scanErr := SimpleBleAdapterScanFor(adapter, SCAN_TIMEOUT_MS);
        if scanErr <> SIMPLEBLE_SUCCESS then
        begin
            if isCancelRequested() then
            begin
                writeScanCancelled();
                scanCancelled := True;
            end
            else
                writeBleScanLine(Flogger, 'scan_start', 'error',
                    'ERROR: BLE scan failed.');
            Exit;
        end;

        scanCount := SimpleBleAdapterScanGetResultsCount(adapter);
        writeBleScanCountLine(Flogger, 'scan_results', 'info',
            Format('Found %d BLE device(s).', [scanCount]), scanCount);

        for i := 0 to scanCount - 1 do
        begin
            if isCancelRequested() then
            begin
                scanCancelled := True;
                Break;
            end;

            Inc(aResult.FoundCount);
            peripheral := SimpleBleAdapterScanGetResultsHandle(adapter, i);
            identifier := SimpleBlePeripheralIdentifier(peripheral);
            address := SimpleBlePeripheralAddress(peripheral);
            if identifier <> nil then
                identStr := string(identifier)
            else
                identStr := '';
            if address <> nil then
                addrStr := string(address)
            else
                addrStr := '';
            if identifier <> nil then
                SimpleBleFree(identifier);
            if address <> nil then
                SimpleBleFree(address);

            writeBleScanLine(Flogger, 'scan_results', 'info',
                Format('  [%d] %s [%s]', [i + 1, identStr, addrStr]));

            currentDevice.Index := i + 1;
            currentDevice.Mac := addrStr;
            currentDevice.Identifier := identStr;
            currentDevice.DeviceType := 'UNKNOWN';
            currentDevice.ComPort := '';
            currentDevice.Peripheral := 0;
            currentDevice.Connectable := False;
            currentDevice.Connected := False;
            currentDevice.MatchesFilters := False;
            currentDevice.HasHeartRate := False;
            currentDevice.ComPort := findComPortForMac(addrStr, wmiDevices);

            if not passesPreConnectFilters(aFilters, currentDevice) then
            begin
                Inc(aResult.SkippedByFilterCount);
                appendDevice(aResult.Devices, currentDevice);
                SimpleBlePeripheralReleaseHandle(peripheral);
                Continue;
            end;

            connectedNow := False;
            connectable := False;
            paired := False;
            SimpleBlePeripheralIsConnectable(peripheral, connectable);
            currentDevice.Connectable := connectable;

            if connectable then
            begin
                pairErr := SimpleBlePeripheralIsPaired(peripheral, paired);
                if (pairErr = SIMPLEBLE_SUCCESS) and (not paired) then
                begin
                    writeBleScanLine(Flogger, 'connect_attempt', 'info',
                        Format('  Pairing attempt for %s [%s]...', [identStr, addrStr]));
                    connectedNow := tryConnectPeripheral(peripheral, CONNECT_TIMEOUT_MS);
                end;

                if not connectedNow then
                    connectedNow := tryConnectPeripheral(peripheral, CONNECT_TIMEOUT_MS);

                if isCancelRequested() then
                begin
                    scanCancelled := True;
                    if connectedNow then
                        SimpleBlePeripheralDisconnect(peripheral);
                    SimpleBlePeripheralReleaseHandle(peripheral);
                    Break;
                end;

                if connectedNow then
                begin
                    currentDevice.Connected := True;
                    Inc(aResult.ConnectedCount);
                    currentDevice.DeviceType := classifyDeviceByServices(peripheral);
                    currentDevice.HasHeartRate := peripheralHasHrService(peripheral);
                end
                else
                begin
                    Inc(aResult.ConnectFailCount);
                    writeBleDeviceError(Flogger, addrStr,
                        Format('  Connect failed/timeout for %s [%s]', [identStr, addrStr]));
                end;
            end
            else
            begin
                Inc(aResult.NotConnectableCount);
                writeBleDeviceError(Flogger, addrStr,
                    Format('  Not connectable: %s [%s]', [identStr, addrStr]));
            end;

            currentDevice.MatchesFilters := deviceMatchesFilters(aFilters, currentDevice);

            if (Length(aFilters) > 0) and (not currentDevice.MatchesFilters) then
                Inc(aResult.SkippedByFilterCount);

            if currentDevice.MatchesFilters then
            begin
                Inc(aResult.MatchedCount);
                if (aResult.FirstMatchedPeripheral = 0) and aKeepFirstMatchedConnected and connectedNow then
                begin
                    aResult.FirstMatchedPeripheral := peripheral;
                    aResult.FirstMatchedMac := currentDevice.Mac;
                    aResult.FirstMatchedIdentifier := currentDevice.Identifier;
                end;
            end;

            if aRetainPeripheralHandles then
            begin
                currentDevice.Peripheral := peripheral;
                hasRetainedHandles := True;
            end;

            appendDevice(aResult.Devices, currentDevice);

            if aRetainPeripheralHandles then
            begin
                if connectedNow then
                    SimpleBlePeripheralDisconnect(peripheral);
            end
            else
            begin
                if (aResult.FirstMatchedPeripheral <> peripheral) and connectedNow then
                    SimpleBlePeripheralDisconnect(peripheral);

                if aResult.FirstMatchedPeripheral <> peripheral then
                    SimpleBlePeripheralReleaseHandle(peripheral);
            end;

            if (not aFullScan) and (Length(aFilters) > 0) and (aResult.MatchedCount > 0) then
                Break;
        end;

        if scanCancelled then
        begin
            writeScanCancelled();
            Exit;
        end;

        if Length(aFilters) > 0 then
            writeBleScanCountLine(Flogger, 'filter_results', 'info',
                Format('Skipped by filter: %d device(s).', [aResult.SkippedByFilterCount]),
                aResult.SkippedByFilterCount);

        writeBleScanCountLine(Flogger, 'connect_results', 'info',
            Format('Connected %d device(s).', [aResult.ConnectedCount]), aResult.ConnectedCount);
        writeBleScanCountLine(Flogger, 'connect_results', 'info',
            Format('Connect failed for %d device(s).', [aResult.ConnectFailCount]), aResult.ConnectFailCount);
        writeBleScanCountLine(Flogger, 'connect_results', 'info',
            Format('Not connectable: %d device(s).', [aResult.NotConnectableCount]), aResult.NotConnectableCount);
        writeBleScanCountLine(Flogger, 'scan_summary', 'info',
            Format('Processed %d scanned device(s).', [aResult.FoundCount]), aResult.FoundCount);

        Result := True;
    finally
        EnterCriticalSection(FscanLock);
        try
            FscanAdapter := 0;
            if adapter <> 0 then
            begin
                SimpleBleAdapterReleaseHandle(adapter);
                adapter := 0;
            end;
        finally
            LeaveCriticalSection(FscanLock);
        end;

        if bleReady then
        begin
            if (aKeepFirstMatchedConnected and (aResult.FirstMatchedPeripheral <> 0)) or
                (aRetainPeripheralHandles and hasRetainedHandles) then
                aResult.BleLibraryLoaded := True
            else
                SimpleBleUnloadLibrary();
        end;
    end;
end;

end.
