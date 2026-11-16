# Icom TimeSync

**Icom TimeSync** is a simple Windows utility for synchronizing the internal UTC date and time of Icom transceivers via USB CAT (CI-V).

### Supported radios
- Icom IC-7300
- Icom IC-9700
- Icom IC-705

### Features
- Synchronizes radio date and time with the computer's UTC clock.
- Sets the radio's UTC offset to 00:00.
- Waits for the next full minute before sending the time, providing accurate synchronization.
- Uses USB CAT / CI-V communication.

### Requirements
- Windows
- USB CAT connection to the radio
- Configured COM port and CI-V communication settings

### Installation and usage
1. Download the project files.
2. Extract both files into the same folder:
   - `Icom_TimeSync.bat` 
   - `Icom_TimeSync.ps1` (Czech)
   - `Icom_TimeSync_EN.ps1` (English)
3. Connect your Icom transceiver via USB.
4. Run `Icom_TimeSync.bat`.

Follow the on-screen instructions.

### License
Free to use and share for amateur radio purposes.

**73!**
