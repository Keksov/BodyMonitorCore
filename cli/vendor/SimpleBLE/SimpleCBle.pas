unit SimpleCBle;

{$mode ObjFPC}{$H+}
{$macro on}

{ Lazarus / Free Pascal bindings for the cross-platform SimpleBLE library.

  Pascal bindings are Copyright (c) 2022-2023 Erik Lins and released under the MIT License.
    https://github.com/eriklins/Pascal-Bindings-For-SimpleBLE-Library

  Modified for KKMindWave SimpleCBLE v0.12.1 migration.

  The SimpleBLE library is Copyright (c) 2021-2022 Kevin Dewald and released under the MIT License.
    https://github.com/OpenBluetoothToolbox/SimpleBLE
}

interface

uses
  Classes, SysUtils, DynLibs;

const
  SimpleBleExtLibrary = 'simplecble.dll';

  {$IFDEF FPC}
  {$PACKRECORDS C}
  {$ENDIF}

  //#define SIMPLEBLE_UUID_STR_LEN 37  // 36 characters + null terminator
  //#define SIMPLEBLE_CHARACTERISTIC_MAX_COUNT 16
  //#define SIMPLEBLE_DESCRIPTOR_MAX_COUNT 16
  //Note: in C array declaration the above is the number of elements,
  //hence in Pascal we need to subtract 1 in the array declaration
  //like array[0..SIMPLEBLE_UUID_STR_LEN-1]
  SIMPLEBLE_UUID_STR_LEN = 37;
  SIMPLEBLE_CHARACTERISTIC_MAX_COUNT = 16;
  SIMPLEBLE_DESCRIPTOR_MAX_COUNT = 16;


{ types from SimpleBLE types.h }

type
  //typedef enum {
  //    SIMPLEBLE_SUCCESS = 0,
  //    SIMPLEBLE_FAILURE = 1,
  //} simpleble_err_t;
  TSimpleBleErr = (SIMPLEBLE_SUCCESS = 0, SIMPLEBLE_FAILURE = 1);

  //typedef struct {
  //  char value[SIMPLEBLE_UUID_STR_LEN];
  //} simpleble_uuid_t;
  TSimpleBleUuid = record
    Value: array[0..SIMPLEBLE_UUID_STR_LEN-1] of Char;
  end;

  //typedef struct {
  //    simpleble_uuid_t uuid;
  //} simpleble_descriptor_t;
  TSimpleBleDescriptor = record
    Uuid: TSimpleBleUuid;
  end;

  //typedef struct {
  //    simpleble_uuid_t uuid;
  //    bool can_read;
  //    bool can_write_request;
  //    bool can_write_command;
  //    bool can_notify;
  //    bool can_indicate;
  //    size_t descriptor_count;
  //    simpleble_descriptor_t descriptors[SIMPLEBLE_DESCRIPTOR_MAX_COUNT];
  //} simpleble_characteristic_t;
  TSimpleBleCharacteristic = record
    Uuid: TSimpleBleUuid;
    CanRead: Boolean;
    CanWriteRequest: Boolean;
    CanWriteCommand: Boolean;
    CanNotify: Boolean;
    CanIndicate: Boolean;
    DescriptorCount: NativeUInt;
    Descriptors: array[0..SIMPLEBLE_DESCRIPTOR_MAX_COUNT-1] of TSimpleBleDescriptor;
  end;

  //typedef struct {
  //    simpleble_uuid_t uuid;
  //    size_t data_length;
  //    uint8_t data[27];
  //    // Note: The maximum length of a BLE advertisement is 31 bytes.
  //    // The first byte will be the length of the field,
  //    // the second byte will be the type of the field,
  //    // the next two bytes will be the service UUID,
  //    // and the remaining 27 bytes are the manufacturer data.
  //    size_t characteristic_count;
  //    simpleble_characteristic_t characteristics[SIMPLEBLE_CHARACTERISTIC_MAX_COUNT];
  //} simpleble_service_t;
  TSimpleBleService = record
    Uuid: TSimpleBleUuid;
    DataLength: NativeUInt;
    Data: array[0..27-1] of Byte;
    CharacteristicCount: NativeUInt;
    Characteristics: array[0..SIMPLEBLE_CHARACTERISTIC_MAX_COUNT-1] of TSimpleBleCharacteristic;
  end;

  //typedef struct {
  //    uint16_t manufacturer_id;
  //    size_t data_length;
  //    uint8_t data[27];
  //    // Note: The maximum length of a BLE advertisement is 31 bytes.
  //    // The first byte will be the length of the field,
  //    // the second byte will be the type of the field (0xFF for manufacturer data),
  //    // the next two bytes will be the manufacturer ID,
  //    // and the remaining 27 bytes are the manufacturer data.
  //} simpleble_manufacturer_data_t;
  TSimpleBleManufacturerData = record
    ManufacturerId: UInt16;
    DataLength: NativeUInt;
    Data: array[0..27-1] of Byte
  end;

  //typedef void* simpleble_adapter_t;
  //typedef void* simpleble_peripheral_t;
  TSimpleBleAdapter = NativeUInt;
  TSimpleBlePeripheral = NativeUInt;

  //typedef enum {
  //  SIMPLEBLE_OS_WINDOWS = 0,
  //  SIMPLEBLE_OS_MACOS = 1,
  //  SIMPLEBLE_OS_LINUX = 2,
  //} simpleble_os_t;
  TSimpleBleOs = (SIMPLEBLE_OS_WINDOWS = 0, SIMPLEBLE_OS_MACOS = 1, SIMPLEBLE_OS_LINUX = 2);

  //typedef enum {
  //    SIMPLEBLE_ADDRESS_TYPE_PUBLIC = 0,
  //    SIMPLEBLE_ADDRESS_TYPE_RANDOM = 1,
  //    SIMPLEBLE_ADDRESS_TYPE_UNSPECIFIED = 2,
  //} simpleble_address_type_t;
  TSimpleBleAddressType = (SIMPLEBLE_ADDRESS_TYPE_PUBLIC = 0, SIMPLEBLE_ADDRESS_TYPE_RANDOM = 1, SIMPLEBLE_ADDRESS_TYPE_UNSPECIFIED = 2);


// Windows x64 build keeps only the dynamic-loading path.

// the below is for dynamically loading the DLL libraries on Windows only!


// define function for dynamically loading/unloading the DLL
function SimpleBleLoadLibrary(dllPath:string=''): Boolean;
procedure SimpleBleUnloadLibrary();


{ functions from SimpleBLE adapter.h }

type
  TSimpleBleCallbackScanStart = procedure(Adapter: TSimpleBleAdapter; UserData: Pointer); cdecl;
  TSimpleBleCallbackScanStop = procedure(Adapter: TSimpleBleAdapter; UserData: Pointer); cdecl;
  TSimpleBleCallbackScanUpdated = procedure(Adapter: TSimpleBleAdapter; Peripheral: TSimpleBlePeripheral; UserData: Pointer); cdecl;
  TSimpleBleCallbackScanFound = procedure(Adapter: TSimpleBleAdapter; Peripheral: TSimpleBlePeripheral; UserData: Pointer); cdecl;

var
  SimpleBleAdapterIsBluetoothEnabled : function() : Boolean; cdecl;
  SimpleBleAdapterGetCount : function() : NativeUInt; cdecl;
  SimpleBleAdapterGetHandle : function(Index: NativeUInt): TSimpleBleAdapter; cdecl;
  SimpleBleAdapterReleaseHandle : procedure(Handle: TSimpleBleAdapter); cdecl;
  SimpleBleAdapterIdentifier : function(Handle: TSimpleBleAdapter): PChar; cdecl;
  SimpleBleAdapterAddress : function(Handle: TSimpleBleAdapter): PChar; cdecl;
  SimpleBleAdapterScanStart : function(Handle: TSimpleBleAdapter): TSimpleBleErr; cdecl;
  SimpleBleAdapterScanStop : function(Handle: TSimpleBleAdapter): TSimpleBleErr; cdecl;
  SimpleBleAdapterScanIsActive : function(Handle: TSimpleBleAdapter; var Active: Boolean): TSimpleBleErr; cdecl;
  SimpleBleAdapterScanFor : function(Handle: TSimpleBleAdapter; TimeoutMs: Integer): TSimpleBleErr; cdecl;
  SimpleBleAdapterScanGetResultsCount : function(Handle: TSimpleBleAdapter): NativeUInt; cdecl;
  SimpleBleAdapterScanGetResultsHandle : function(Handle: TSimpleBleAdapter; Index: NativeUInt): TSimpleBlePeripheral; cdecl;
  SimpleBleAdapterGetPairedPeripheralsCount : function(Handle: TSimpleBleAdapter): NativeUInt; cdecl;
  SimpleBleAdapterGetPairedPeripheralsHandle : function(Handle: TSimpleBleAdapter; Index: NativeUInt): TSimpleBlePeripheral; cdecl;
  SimpleBleAdapterSetCallbackOnScanStart : function(Handle: TSimpleBleAdapter; Callback: TSimpleBleCallbackScanStart; UserData: Pointer): TSimpleBleErr;  cdecl;
  SimpleBleAdapterSetCallbackOnScanStop : function(Handle: TSimpleBleAdapter; Callback: TSimpleBleCallbackScanStop; UserData: Pointer): TSimpleBleErr; cdecl;
  SimpleBleAdapterSetCallbackOnScanUpdated : function(Handle: TSimpleBleAdapter; Callback: TSimpleBleCallbackScanUpdated; UserData: Pointer): TSimpleBleErr; cdecl;
  SimpleBleAdapterSetCallbackOnScanFound : function(Handle: TSimpleBleAdapter; Callback: TSimpleBleCallbackScanFound; UserData: Pointer): TSimpleBleErr; cdecl;


{ functions from SimpleBLE peripheral.h }

type
  TSimpleBleCallbackOnConnected = procedure(Peripheral: TSimpleBlePeripheral; UserData: Pointer); cdecl;
  TSimpleBleCallbackOnDisconnected = procedure(Peripheral: TSimpleBlePeripheral; UserData: Pointer); cdecl;
  TSimpleBleCallbackNotify = procedure(Peripheral: TSimpleBlePeripheral; Service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Data: PByte; DataLength: NativeUInt; UserData: Pointer); cdecl;
  TSimpleBleCallbackIndicate = procedure(Peripheral: TSimpleBlePeripheral; Service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Data: PByte; DataLength: NativeUInt; UserData: Pointer); cdecl;

var
  SimpleBlePeripheralReleaseHandle : procedure(Handle: TSimpleBlePeripheral); cdecl;
  SimpleBlePeripheralIdentifier : function(Handle: TSimpleBlePeripheral): PChar; cdecl;
  SimpleBlePeripheralAddress : function(Handle: TSimpleBlePeripheral): PChar; cdecl;
  SimpleBlePeripheralAddressType : function(Handle: TSimpleBlePeripheral): TSimpleBleAddressType; cdecl;
  SimpleBlePeripheralRssi : function(Handle: TSimpleBlePeripheral): Int16; cdecl;
  SimpleBlePeripheralTxPower : function(Handle: TSimpleBlePeripheral): Int16; cdecl;
  SimpleBlePeripheralMtu : function(Handle: TSimpleBlePeripheral): UInt16; cdecl;
  SimpleBlePeripheralConnect : function(Handle: TSimpleBlePeripheral): TSimpleBleErr; cdecl;
  SimpleBlePeripheralDisconnect : function(Handle: TSimpleBlePeripheral): TSimpleBleErr; cdecl;
  SimpleBlePeripheralIsConnected : function(Handle: TSimpleBlePeripheral; var connected: Boolean): TSimpleBleErr; cdecl;
  SimpleBlePeripheralIsConnectable : function(Handle: TSimpleBlePeripheral; var connectable: Boolean): TSimpleBleErr; cdecl;
  SimpleBlePeripheralIsPaired : function(Handle: TSimpleBlePeripheral; var paired: Boolean): TSimpleBleErr; cdecl;
  SimpleBlePeripheralUnpair : function(Handle: TSimpleBlePeripheral): TSimpleBleErr; cdecl;
  SimpleBlePeripheralServicesCount : function(Handle: TSimpleBlePeripheral): NativeUInt; cdecl;
  SimpleBlePeripheralServicesGet : function(Handle: TSimpleBlePeripheral; Index: NativeUInt; var Services: TSimpleBleService): TSimpleBleErr; cdecl;
  SimpleBlePeripheralManufacturerDataCount : function(Handle: TSimpleBlePeripheral): NativeUInt; cdecl;
  SimpleBlePeripheralManufacturerDataGet : function(Handle: TSimpleBlePeripheral; Index: NativeUInt; var ManufacturerData: TSimpleBleManufacturerData): TSimpleBleErr; cdecl;
  SimpleBlePeripheralRead : function(Handle: TSimpleBlePeripheral; service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; var Data: PByte; var DataLength: NativeUInt): TSimpleBleErr; cdecl;
  SimpleBlePeripheralWriteRequest : function(Handle: TSimpleBlePeripheral; service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Data: PByte; DataLength: NativeUInt): TSimpleBleErr; cdecl;
  SimpleBlePeripheralWriteCommand : function(Handle: TSimpleBlePeripheral; service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Data: PByte; DataLength: NativeUInt): TSimpleBleErr; cdecl;
  SimpleBlePeripheralNotify : function(Handle: TSimpleBlePeripheral; Service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Callback: TSimpleBleCallbackNotify; UserData: Pointer): TSimpleBleErr; cdecl;
  SimpleBlePeripheralIndicate : function(Handle: TSimpleBlePeripheral; Service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Callback: TSimpleBleCallbackIndicate; UserData: Pointer): TSimpleBleErr; cdecl;
  SimpleBlePeripheralUnsubscribe : function(Handle: TSimpleBlePeripheral; service: TSimpleBleUuid; Characteristic: TSimpleBleUuid):TSimpleBleErr; cdecl;
  SimpleBlePeripheralReadDescriptor : function(Handle: TSimpleBlePeripheral; service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Descriptor: TSimpleBleUuid; var Data: PByte; var DataLength: NativeUInt): TSimpleBleErr; cdecl;
  SimpleBlePeripheralWriteDescriptor : function(Handle: TSimpleBlePeripheral; service: TSimpleBleUuid; Characteristic: TSimpleBleUuid; Descriptor: TSimpleBleUuid; Data: PByte; DataLength: NativeUInt): TSimpleBleErr; cdecl;
  SimpleBlePeripheralSetCallbackOnConnected : function(Handle: TSimpleBlePeripheral; Callback: TSimpleBleCallbackOnConnected; UserData: Pointer): TSimpleBleErr; cdecl;
  SimpleBlePeripheralSetCallbackOnDisconnected : function(Handle: TSimpleBlePeripheral; Callback: TSimpleBleCallbackOnDisconnected; UserData: Pointer): TSimpleBleErr; cdecl;


{ functions from SimpleBLE simpleble.h }

var
  SimpleBleFree : procedure(Handle: Pointer); cdecl;


{ functions from SimpleBLE logging.h }

type
  TSimpleBleLogLevel = (SIMPLEBLE_LOG_LEVEL_NONE    = 0,
                        SIMPLEBLE_LOG_LEVEL_FATAL   = 1,
                        SIMPLEBLE_LOG_LEVEL_ERROR   = 2,
                        SIMPLEBLE_LOG_LEVEL_WARN    = 3,
                        SIMPLEBLE_LOG_LEVEL_INFO    = 4,
                        SIMPLEBLE_LOG_LEVEL_DEBUG   = 5,
                        SIMPLEBLE_LOG_LEVEL_VERBOSE = 6);

  TCallbackLog = procedure(Level: TSimpleBleLogLevel; Module: PChar; LFile: PChar; Line: DWord; LFunction: PChar; LMessage: PChar);

var
  SimpleBleLoggingSetLevel : procedure(Level: TSimpleBleLogLevel); cdecl;
  SimpleBleloggingSetCallback : procedure(Callback: TCallbackLog); cdecl;


{ functions from SimpleBLE utils.h }

//var
  SimpleBleGetOperatingSystem : function(): TSimpleBleOs; cdecl;
  SimpleBleGetVersion : function(): PChar; cdecl;

implementation

var
  hLib : TLibHandle = 0;

function RequiredSymbolsLoaded: Boolean;
begin
  Result :=
    (pointer(SimpleBleAdapterIsBluetoothEnabled) <> Nil) and
    (pointer(SimpleBleAdapterGetCount) <> Nil) and
    (pointer(SimpleBleAdapterGetHandle) <> Nil) and
    (pointer(SimpleBleAdapterReleaseHandle) <> Nil) and
    (pointer(SimpleBleAdapterScanStart) <> Nil) and
    (pointer(SimpleBleAdapterScanStop) <> Nil) and
    (pointer(SimpleBleAdapterScanIsActive) <> Nil) and
    (pointer(SimpleBleAdapterScanFor) <> Nil) and
    (pointer(SimpleBleAdapterScanGetResultsCount) <> Nil) and
    (pointer(SimpleBleAdapterScanGetResultsHandle) <> Nil) and
    (pointer(SimpleBleAdapterSetCallbackOnScanUpdated) <> Nil) and
    (pointer(SimpleBleAdapterSetCallbackOnScanFound) <> Nil) and
    (pointer(SimpleBlePeripheralReleaseHandle) <> Nil) and
    (pointer(SimpleBlePeripheralIdentifier) <> Nil) and
    (pointer(SimpleBlePeripheralAddress) <> Nil) and
    (pointer(SimpleBlePeripheralConnect) <> Nil) and
    (pointer(SimpleBlePeripheralDisconnect) <> Nil) and
    (pointer(SimpleBlePeripheralIsConnected) <> Nil) and
    (pointer(SimpleBlePeripheralIsConnectable) <> Nil) and
    (pointer(SimpleBlePeripheralIsPaired) <> Nil) and
    (pointer(SimpleBlePeripheralServicesCount) <> Nil) and
    (pointer(SimpleBlePeripheralServicesGet) <> Nil) and
    (pointer(SimpleBlePeripheralNotify) <> Nil) and
    (pointer(SimpleBlePeripheralUnsubscribe) <> Nil) and
    (pointer(SimpleBlePeripheralSetCallbackOnDisconnected) <> Nil) and
    (pointer(SimpleBleFree) <> Nil) and
    (pointer(SimpleBleLoggingSetLevel) <> Nil) and
    (pointer(SimpleBleGetVersion) <> Nil);
end;


{ Clear the pointers to the functions and procedures }
procedure ClearPointers;
begin
  { functions from SimpleBLE adapter.h }
  pointer(SimpleBleAdapterIsBluetoothEnabled) := Nil;
  pointer(SimpleBleAdapterGetCount) := Nil;
  pointer(SimpleBleAdapterGetHandle) := Nil;
  pointer(SimpleBleAdapterReleaseHandle) := Nil;
  pointer(SimpleBleAdapterIdentifier) := Nil;
  pointer(SimpleBleAdapterAddress) := Nil;
  pointer(SimpleBleAdapterScanStart) := Nil;
  pointer(SimpleBleAdapterScanStop) := Nil;
  pointer(SimpleBleAdapterScanIsActive) := Nil;
  pointer(SimpleBleAdapterScanFor) := Nil;
  pointer(SimpleBleAdapterScanGetResultsCount) := Nil;
  pointer(SimpleBleAdapterScanGetResultsHandle) := Nil;
  pointer(SimpleBleAdapterGetPairedPeripheralsCount) := Nil;
  pointer(SimpleBleAdapterGetPairedPeripheralsHandle) := Nil;
  pointer(SimpleBleAdapterSetCallbackOnScanStart) := Nil;
  pointer(SimpleBleAdapterSetCallbackOnScanStop) := Nil;
  pointer(SimpleBleAdapterSetCallbackOnScanUpdated) := Nil;
  pointer(SimpleBleAdapterSetCallbackOnScanFound) := Nil;

  { functions from SimpleBLE peripheral.h }
  pointer(SimpleBlePeripheralReleaseHandle) := Nil;
  pointer(SimpleBlePeripheralIdentifier) := Nil;
  pointer(SimpleBlePeripheralAddress) := Nil;
  pointer(SimpleBlePeripheralAddressType) := Nil;
  pointer(SimpleBlePeripheralRssi) := Nil;
  pointer(SimpleBlePeripheralTxPower) := Nil;
  pointer(SimpleBlePeripheralMtu) := Nil;
  pointer(SimpleBlePeripheralConnect) := Nil;
  pointer(SimpleBlePeripheralDisconnect) := Nil;
  pointer(SimpleBlePeripheralIsConnected) := Nil;
  pointer(SimpleBlePeripheralIsConnectable) := Nil;
  pointer(SimpleBlePeripheralIsPaired) := Nil;
  pointer(SimpleBlePeripheralUnpair) := Nil;
  pointer(SimpleBlePeripheralServicesCount) := Nil;
  pointer(SimpleBlePeripheralServicesGet) := Nil;
  pointer(SimpleBlePeripheralManufacturerDataCount) := Nil;
  pointer(SimpleBlePeripheralManufacturerDataGet) := Nil;
  pointer(SimpleBlePeripheralRead) := Nil;
  pointer(SimpleBlePeripheralWriteRequest) := Nil;
  pointer(SimpleBlePeripheralWriteCommand) := Nil;
  pointer(SimpleBlePeripheralNotify) := Nil;
  pointer(SimpleBlePeripheralIndicate) := Nil;
  pointer(SimpleBlePeripheralUnsubscribe) := Nil;
  pointer(SimpleBlePeripheralReadDescriptor) := Nil;
  pointer(SimpleBlePeripheralWriteDescriptor) := Nil;
  pointer(SimpleBlePeripheralSetCallbackOnConnected) := Nil;
  pointer(SimpleBlePeripheralSetCallbackOnDisconnected) := Nil;

  { functions from SimpleBLE simpleble.h }
  pointer(SimpleBleFree) := Nil;

  { functions from SimpleBLE logging.h }
  pointer(SimpleBleLoggingSetLevel) := Nil;
  pointer(SimpleBleloggingSetCallback) := Nil;

  { functions from SimpleBLE utils.h }
  pointer(SimpleBleGetOperatingSystem) := Nil;
  pointer(SimpleBleGetVersion) := Nil;
  
end;


{ Load the DLL file with an optional path specified }
function SimpleBleLoadLibrary(dllPath:string=''): Boolean;
begin
  result := false;
  ClearPointers;
  if dllPath <> '' then begin
    if not DirectoryExists(dllPath) then exit;
    if rightstr(dllPath,1) <> DirectorySeparator then dllPath := dllPath + DirectorySeparator;
    if not FileExists(dllPath + SimpleBleExtLibrary) then exit;
    hLib := LoadLibrary(PChar(dllPath + SimpleBleExtLibrary));
  end else begin
    hLib := LoadLibrary(PChar(SimpleBleExtLibrary));
  end;
  if hLib = 0 then exit;

  try
    { functions from SimpleBLE adapter.h }
    pointer(SimpleBleAdapterIsBluetoothEnabled) := GetProcedureAddress(hLib, 'simpleble_adapter_is_bluetooth_enabled');
    pointer(SimpleBleAdapterGetCount) := GetProcedureAddress(hLib, 'simpleble_adapter_get_count');
    pointer(SimpleBleAdapterGetHandle) := GetProcedureAddress(hLib, 'simpleble_adapter_get_handle');
    pointer(SimpleBleAdapterReleaseHandle) := GetProcedureAddress(hLib, 'simpleble_adapter_release_handle');
    pointer(SimpleBleAdapterIdentifier) := GetProcedureAddress(hLib, 'simpleble_adapter_identifier');
    pointer(SimpleBleAdapterAddress) := GetProcedureAddress(hLib, 'simpleble_adapter_address');
    pointer(SimpleBleAdapterScanStart) := GetProcedureAddress(hLib, 'simpleble_adapter_scan_start');
    pointer(SimpleBleAdapterScanStop) := GetProcedureAddress(hLib, 'simpleble_adapter_scan_stop');
    pointer(SimpleBleAdapterScanIsActive) := GetProcedureAddress(hLib, 'simpleble_adapter_scan_is_active');
    pointer(SimpleBleAdapterScanFor) := GetProcedureAddress(hLib, 'simpleble_adapter_scan_for');
    pointer(SimpleBleAdapterScanGetResultsCount) := GetProcedureAddress(hLib, 'simpleble_adapter_scan_get_results_count');
    pointer(SimpleBleAdapterScanGetResultsHandle) := GetProcedureAddress(hLib, 'simpleble_adapter_scan_get_results_handle');
    pointer(SimpleBleAdapterGetPairedPeripheralsCount) := GetProcedureAddress(hLib, 'simpleble_adapter_get_paired_peripherals_count');
    pointer(SimpleBleAdapterGetPairedPeripheralsHandle) := GetProcedureAddress(hLib, 'simpleble_adapter_get_paired_peripherals_handle');
    pointer(SimpleBleAdapterSetCallbackOnScanStart) := GetProcedureAddress(hLib, 'simpleble_adapter_set_callback_on_scan_start');
    pointer(SimpleBleAdapterSetCallbackOnScanStop) := GetProcedureAddress(hLib, 'simpleble_adapter_set_callback_on_scan_stop');
    pointer(SimpleBleAdapterSetCallbackOnScanUpdated) := GetProcedureAddress(hLib, 'simpleble_adapter_set_callback_on_scan_updated');
    pointer(SimpleBleAdapterSetCallbackOnScanFound) := GetProcedureAddress(hLib, 'simpleble_adapter_set_callback_on_scan_found');

    { functions from SimpleBLE peripheral.h }
    pointer(SimpleBlePeripheralReleaseHandle) := GetProcedureAddress(hLib, 'simpleble_peripheral_release_handle');
    pointer(SimpleBlePeripheralIdentifier) := GetProcedureAddress(hLib, 'simpleble_peripheral_identifier');
    pointer(SimpleBlePeripheralAddress) := GetProcedureAddress(hLib, 'simpleble_peripheral_address');
    pointer(SimpleBlePeripheralAddressType) := GetProcedureAddress(hLib, 'simpleble_peripheral_address_type');
    pointer(SimpleBlePeripheralRssi) := GetProcedureAddress(hLib, 'simpleble_peripheral_rssi');
    pointer(SimpleBlePeripheralTxPower) := GetProcedureAddress(hLib, 'simpleble_peripheral_tx_power');
    pointer(SimpleBlePeripheralMtu) := GetProcedureAddress(hLib, 'simpleble_peripheral_mtu');
    pointer(SimpleBlePeripheralConnect) := GetProcedureAddress(hLib, 'simpleble_peripheral_connect');
    pointer(SimpleBlePeripheralDisconnect) := GetProcedureAddress(hLib, 'simpleble_peripheral_disconnect');
    pointer(SimpleBlePeripheralIsConnected) := GetProcedureAddress(hLib, 'simpleble_peripheral_is_connected');
    pointer(SimpleBlePeripheralIsConnectable) := GetProcedureAddress(hLib, 'simpleble_peripheral_is_connectable');
    pointer(SimpleBlePeripheralIsPaired) := GetProcedureAddress(hLib, 'simpleble_peripheral_is_paired');
    pointer(SimpleBlePeripheralUnpair) := GetProcedureAddress(hLib, 'simpleble_peripheral_unpair');
    pointer(SimpleBlePeripheralServicesCount) := GetProcedureAddress(hLib, 'simpleble_peripheral_services_count');
    pointer(SimpleBlePeripheralServicesGet) := GetProcedureAddress(hLib, 'simpleble_peripheral_services_get');
    pointer(SimpleBlePeripheralManufacturerDataCount) := GetProcedureAddress(hLib, 'simpleble_peripheral_manufacturer_data_count');
    pointer(SimpleBlePeripheralManufacturerDataGet) := GetProcedureAddress(hLib, 'simpleble_peripheral_manufacturer_data_get');
    pointer(SimpleBlePeripheralRead) := GetProcedureAddress(hLib, 'simpleble_peripheral_read');
    pointer(SimpleBlePeripheralWriteRequest) := GetProcedureAddress(hLib, 'simpleble_peripheral_write_request');
    pointer(SimpleBlePeripheralWriteCommand) := GetProcedureAddress(hLib, 'simpleble_peripheral_write_command');
    pointer(SimpleBlePeripheralNotify) := GetProcedureAddress(hLib, 'simpleble_peripheral_notify');
    pointer(SimpleBlePeripheralIndicate) := GetProcedureAddress(hLib, 'simpleble_peripheral_indicate');
    pointer(SimpleBlePeripheralUnsubscribe) := GetProcedureAddress(hLib, 'simpleble_peripheral_unsubscribe');
    pointer(SimpleBlePeripheralReadDescriptor) := GetProcedureAddress(hLib, 'simpleble_peripheral_read_descriptor');
    pointer(SimpleBlePeripheralWriteDescriptor) := GetProcedureAddress(hLib, 'simpleble_peripheral_write_descriptor');
    pointer(SimpleBlePeripheralSetCallbackOnConnected) := GetProcedureAddress(hLib, 'simpleble_peripheral_set_callback_on_connected');
    pointer(SimpleBlePeripheralSetCallbackOnDisconnected) := GetProcedureAddress(hLib, 'simpleble_peripheral_set_callback_on_disconnected');

    { functions from SimpleBLE simpleble.h }
    pointer(SimpleBleFree) := GetProcedureAddress(hLib, 'simpleble_free');

    { functions from SimpleBLE logging.h }
    pointer(SimpleBleLoggingSetLevel) := GetProcedureAddress(hLib, 'simpleble_logging_set_level');
    pointer(SimpleBleloggingSetCallback) := GetProcedureAddress(hLib, 'simpleble_logging_set_callback');

    { functions from SimpleBLE utils.h }
    pointer(SimpleBleGetOperatingSystem) := GetProcedureAddress(hLib, 'simpleble_get_operating_system');
	pointer(SimpleBleGetVersion) := GetProcedureAddress(hLib, 'simpleble_get_version');
	
  except
    SimpleBleUnloadLibrary;
    exit;
  end;

  if not RequiredSymbolsLoaded then
  begin
    //writeln('Fail');
    SimpleBleUnloadLibrary;
    exit;
  end;
  //writeln('Success');
  result:=true;
end;


{ Unload the DLL }
procedure SimpleBleUnloadLibrary();
begin
  ClearPointers;
  if hLib <> 0 then
  begin
    UnloadLibrary(hLib);
    hLib := 0;
  end;
end;

end.

