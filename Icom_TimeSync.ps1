# Icom_TimeSync.ps1 - version 6
# Synchronizace data a casu Windows do Icom IC-7300 / IC-9700 pres USB CI-V.

$ErrorActionPreference = "Stop"

function ConvertTo-Bcd([int]$Value) {
    if ($Value -lt 0 -or $Value -gt 99) { throw "Hodnota mimo rozsah BCD: $Value" }
    $tens = [int][Math]::Floor($Value / 10.0)
    $ones = $Value % 10
    return [byte](($tens -shl 4) -bor $ones)
}

function Convert-BytesToHexText([byte[]]$DataBytes) {
    return (($DataBytes | ForEach-Object { $_.ToString("X2") }) -join " ")
}

function Send-CivCommand($Port, [byte]$RadioAddress, [byte[]]$CommandData, [string]$Label) {
    # CI-V frame: radio address, controller address E0, command, data, FD.
    [byte[]]$Frame = @([byte]0xFE, [byte]0xFE, $RadioAddress, [byte]0xE0) + $CommandData + @([byte]0xFD)
    $Port.DiscardInBuffer()
    $Port.Write($Frame, 0, $Frame.Length)

    $Reply = [System.Collections.Generic.List[byte]]::new()
    $Deadline = [DateTime]::UtcNow.AddMilliseconds(900)
    while ([DateTime]::UtcNow -lt $Deadline) {
        while ($Port.BytesToRead -gt 0) {
            $b = $Port.ReadByte()
            if ($b -ge 0) { $Reply.Add([byte]$b) }
        }
        if ($Reply.Count -ge 6 -and $Reply.Contains([byte]0xFD)) { break }
        Start-Sleep -Milliseconds 20
    }

    Write-Host "$Label :" -ForegroundColor Cyan
    Write-Host "  TX: $(Convert-BytesToHexText $Frame)"
    if ($Reply.Count -eq 0) {
        Write-Host "  RX: (zadna odpoved)" -ForegroundColor Red
        return $false
    }

    [byte[]]$ReplyBytes = $Reply.ToArray()
    Write-Host "  RX: $(Convert-BytesToHexText $ReplyBytes)"

    # Radio may echo the command frame first, followed by ACK/NG.
    $AckFrame = @([byte]0xFE, [byte]0xFE, [byte]0xE0, $RadioAddress, [byte]0xFB, [byte]0xFD)
    $NgFrame  = @([byte]0xFE, [byte]0xFE, [byte]0xE0, $RadioAddress, [byte]0xFA, [byte]0xFD)

    $replyText = Convert-BytesToHexText $ReplyBytes
    $ackText = Convert-BytesToHexText ([byte[]]$AckFrame)
    $ngText = Convert-BytesToHexText ([byte[]]$NgFrame)

    if ($replyText.EndsWith($ackText)) {
        Write-Host "  Potvrzeno: radio vratilo ACK." -ForegroundColor Green
        return $true
    }
    if ($replyText.EndsWith($ngText)) {
        Write-Host "  Odmitnuto: radio vratilo NG." -ForegroundColor Red
        return $false
    }

    Write-Host "  Odpoved neobsahuje rozpoznane ACK/NG." -ForegroundColor Yellow
    return $false
}

Clear-Host
Write-Host "=========================================================="
Write-Host "       ICOM - UTC SYNCHRONIZACE (7300 / 9700 / 705)"
Write-Host ""
Write-Host "                          (C) OK1UM"
Write-Host "=========================================================="
Write-Host ""
Write-Host "1 - Icom IC-7300"
Write-Host "2 - Icom IC-9700"
Write-Host "3 - Icom IC-705"
Write-Host ""
$choice = Read-Host "Vyber radio (1/2/3)"

switch ($choice) {
    "1" {
        $Model = "IC-7300"
        [byte]$RadioAddress = 0x94
        [byte[]]$DateCommand = @(0x1A, 0x05, 0x00, 0x94)
        [byte[]]$TimeCommand = @(0x1A, 0x05, 0x00, 0x95)
        [byte[]]$OffsetCommand = @(0x1A, 0x05, 0x00, 0x96)
        $DateFormat = "Compact"
        $TimeFormat = "Compact"
    }
    "2" {
        $Model = "IC-9700"
        [byte]$RadioAddress = 0xA2
        [byte[]]$DateCommand = @(0x1A, 0x05, 0x01, 0x79)
        [byte[]]$TimeCommand = @(0x1A, 0x05, 0x01, 0x80)
        [byte[]]$OffsetCommand = @(0x1A, 0x05, 0x01, 0x84)
        $DateFormat = "Compact"
        $TimeFormat = "Compact"
        $OffsetCommand = @(0x1A, 0x05, 0x01, 0x84)
    }
    "3" {
        $Model = "IC-705"
        [byte]$RadioAddress = 0xA4
        [byte[]]$DateCommand = @(0x1A, 0x05, 0x01, 0x65)
        [byte[]]$TimeCommand = @(0x1A, 0x05, 0x01, 0x66)
        [byte[]]$OffsetCommand = @(0x1A, 0x05, 0x01, 0x70)
        $DateFormat = "IC705"
        $TimeFormat = "IC705"
    }
    default {
        Write-Host "Neplatna volba." -ForegroundColor Red
        Read-Host "Stiskni Enter"
        exit 1
    }
}

Write-Host ""
$AvailablePorts = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object)
if ($AvailablePorts.Count -gt 0) {
    Write-Host "Dostupne COM porty: $($AvailablePorts -join ', ')"
} else {
    Write-Host "Windows momentalne nehlasi zadny COM port." -ForegroundColor Yellow
}
$ComPort = Read-Host "Zadej COM port radia"
if ([string]::IsNullOrWhiteSpace($ComPort)) {
    Write-Host "COM port nebyl zadan." -ForegroundColor Red
    Read-Host "Stiskni Enter"
    exit 1
}
$ComPort = $ComPort.Trim().ToUpper()
if ($ComPort -notmatch '^COM\d+$') {
    Write-Host "Neplatny nazev portu: $ComPort" -ForegroundColor Red
    Read-Host "Stiskni Enter"
    exit 1
}

Write-Host ""
Write-Host "Radio:  $Model (CI-V adresa 0x$($RadioAddress.ToString('X2')))"
Write-Host "Port:   $ComPort"
Write-Host "Rychlost: 19200 baud, 8N1"
Write-Host "Synchronizace: odeslani casu na nejblizsi celou minutu UTC"
Write-Host ""
$confirm = Read-Host "Odeslat datum a cas do radia? (A/N)"
if ($confirm -notmatch '^(A|a|Y|y)$') {
    Write-Host "Zruseno."
    Read-Host "Stiskni Enter"
    exit 0
}

$Serial = $null
try {
    $Serial = [System.IO.Ports.SerialPort]::new(
        $ComPort, 19200,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One
    )
    $Serial.Handshake = [System.IO.Ports.Handshake]::None
    $Serial.ReadTimeout = 100
    $Serial.WriteTimeout = 1500
    $Serial.DtrEnable = $false
    $Serial.RtsEnable = $false
    $Serial.Open()

    # Nastavime UTC offset na nulu.
    [byte[]]$OffsetPayload = $OffsetCommand + @([byte]0x00, [byte]0x00, [byte]0x00)
    $OffsetOK = Send-CivCommand $Serial $RadioAddress $OffsetPayload "Nastaveni UTC offsetu na 00:00"

    # Cilova hodnota je nejblizsi nasledujici cela minuta UTC.
    $Now = [DateTime]::UtcNow
    $TargetMinute = [DateTime]::new(
        $Now.Year, $Now.Month, $Now.Day,
        $Now.Hour, $Now.Minute, 0,
        [DateTimeKind]::Utc
    ).AddMinutes(1)

    [byte[]]$DateData = @(
        [byte]0x20,
        (ConvertTo-Bcd ($TargetMinute.Year % 100)),
        (ConvertTo-Bcd $TargetMinute.Month),
        (ConvertTo-Bcd $TargetMinute.Day)
    )
    [byte[]]$TimeData = @(
        (ConvertTo-Bcd $TargetMinute.Hour),
        (ConvertTo-Bcd $TargetMinute.Minute)
    )

    [byte[]]$DatePayload = $DateCommand + $DateData
    [byte[]]$TimePayload = $TimeCommand + $TimeData

    Write-Host ""
    Write-Host "Cilove datum UTC: $($TargetMinute.ToString('yyyy-MM-dd'))"
    Write-Host "Cilovy cas UTC:   $($TargetMinute.ToString('HH:mm')):00"
    $DateOK = Send-CivCommand $Serial $RadioAddress $DatePayload "Nastaveni UTC data"

    # CI-V prikaz ma 11 bajtu, prenos pri 19200 baud trva priblizne 6 ms.
    # Odesleme jej 10 ms pred hranici minuty; posledni bajty by tak mely
    # dorazit velmi blizko zacatku nove minuty.
    $SendAt = $TargetMinute.AddMilliseconds(-10)
    Write-Host ""
    Write-Host "Cekam na synchronizacni okamzik..." -ForegroundColor Cyan

    while ([DateTime]::UtcNow -lt $SendAt.AddMilliseconds(-250)) {
        $remaining = ($SendAt - [DateTime]::UtcNow).TotalSeconds
        Write-Host ("  Odeslani za {0:N1} s   " -f $remaining) -NoNewline
        Start-Sleep -Milliseconds 100
        Write-Host "`r" -NoNewline
    }
    while ([DateTime]::UtcNow -lt $SendAt.AddMilliseconds(-30)) {
        Start-Sleep -Milliseconds 2
    }
    while ([DateTime]::UtcNow -lt $SendAt) {
        # V poslednich milisekundach cekame s co nejmensim zpozdenim.
    }

    Write-Host ""
    Write-Host "Odesilam cas UTC $($TargetMinute.ToString('HH:mm')):00 ..." -ForegroundColor Green
    $ActualSendTime = [DateTime]::UtcNow
    $TimeOK = Send-CivCommand $Serial $RadioAddress $TimePayload "Nastaveni UTC casu na cele minute"
    $ActualDone = [DateTime]::UtcNow
    $LatenessMs = ($ActualDone - $TargetMinute).TotalMilliseconds

    Write-Host ("Zacatek odesilani UTC: {0:HH:mm:ss.fff}" -f $ActualSendTime)
    Write-Host ("Dokonceni komunikace UTC: {0:HH:mm:ss.fff}" -f $ActualDone)
    Write-Host ("Rozdil dokonceni komunikace od hranice minuty: {0:N1} ms" -f $LatenessMs)

    Write-Host ""
    if ($OffsetOK -and $DateOK -and $TimeOK) {
        Write-Host "RADIO POTVRDILO UTC OFFSET, DATUM I CAS (ACK)." -ForegroundColor Green
    } else {
        Write-Host "Nebylo prijato ACK u vsech tri prikazu." -ForegroundColor Yellow
        Write-Host "Zkontroluj datum a cas primo na displeji radia."
    }
    Write-Host "Vysilany cas je UTC; UTC offset radia je nastaven na 00:00."
    Write-Host "Cas je nastaven na zacatku cele minuty UTC; sekundy jsou nastaveny na 00."
}
catch {
    Write-Host ""
    Write-Host "CHYBA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Zkontroluj COM port a nastaveni CI-V USB Baud Rate = 19200."
}
finally {
    if ($Serial -and $Serial.IsOpen) { $Serial.Close() }
}

Write-Host ""
Read-Host "Stiskni Enter pro ukonceni"
