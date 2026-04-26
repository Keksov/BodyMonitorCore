$BleAddress = "e07deae65040"   # твой BLE-адрес без двоеточий
$comPorts = Get-WmiObject -Class "Win32_SerialPort"

foreach ($port in $comPorts) {
    $id = $port.PNPDeviceID
    if ($id -like "*$BleAddress*") {
        Write-Host "Found COM-port for the device ${BleAddress}:"
        Write-Host "  DeviceID: $($port.DeviceID)"
        Write-Host "  PNPDeviceID: ${id}"
        return
    }
}

Write-Host "COM-порт для устройства с адресом $BleAddress не найден."