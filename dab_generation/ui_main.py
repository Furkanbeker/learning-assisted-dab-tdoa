"""
GUI widgets of the DAB TX tool (PySide6).

TxCard     : settings of one transmitter (Pluto URI, DAB channel, gain,
             mode, audio file, IQ output, label, bitrate, duration)
MainWindow : one TxCard plus a log window that shows the output of the
             WSL scripts
"""

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QComboBox,
    QGridLayout, QTextEdit, QFileDialog, QGroupBox, QRadioButton,
    QButtonGroup, QDoubleSpinBox, QSpinBox, QCheckBox, QLineEdit
)
from PySide6.QtCore import Signal, QObject
from tx_manager import PRESETS_HZ, TxSlotConfig


class UiSignals(QObject):
    """Qt signal used to send log lines from worker threads to the GUI."""
    log_line = Signal(str, str)  # slot, line


class TxCard(QGroupBox):
    """Settings panel of one transmit slot."""

    def __init__(self, slot_name: str, signals: UiSignals):
        super().__init__(slot_name)
        self.slot_name = slot_name
        self.signals = signals

        self.serial_label = QLabel("Serial: -")
        self.status_label = QLabel("Status: STOPPED")
        self.status_label.setStyleSheet("font-weight: 800; color: #ef4444;")

        # Pluto URI (editable)
        self.uri_edit = QLineEdit("ip:192.168.2.1")
        self.uri_edit.setPlaceholderText("e.g. ip:192.168.2.1")

        # Frequency presets
        self.freq_combo = QComboBox()
        for k in PRESETS_HZ.keys():
            self.freq_combo.addItem(k)

        idx_8a = self.freq_combo.findText("8A (195.936 MHz)")
        if idx_8a >= 0:
            self.freq_combo.setCurrentIndex(idx_8a)

        # TX gain
        self.gain_spin = QDoubleSpinBox()
        self.gain_spin.setRange(-10.0, 80.0)
        self.gain_spin.setValue(40.0)
        self.gain_spin.setSuffix(" dB")

        # Mode
        self.rb_random = QRadioButton("Random")
        self.rb_file = QRadioButton("File")
        self.rb_record = QRadioButton("Record")
        self.rb_random.setChecked(True)

        self.mode_group = QButtonGroup(self)
        self.mode_group.addButton(self.rb_random)
        self.mode_group.addButton(self.rb_file)
        self.mode_group.addButton(self.rb_record)

        # Audio file
        self.file_label = QLabel("File: (none)")
        self.btn_browse = QPushButton("Browse")

        # IQ output (record mode)
        self.iq_label = QLabel("IQ Output: (none)")
        self.btn_iq_save = QPushButton("Save As...")

        # Service label
        self.label_edit = QLineEdit("MediComm-DAB")

        # Bitrate
        self.bitrate_spin = QSpinBox()
        self.bitrate_spin.setRange(32, 256)
        self.bitrate_spin.setValue(120)
        self.bitrate_spin.setSuffix(" kbps")

        # Duration, loop, track duration
        self.duration_spin = QSpinBox()
        self.duration_spin.setRange(0, 24 * 3600)
        self.duration_spin.setValue(15)
        self.duration_spin.setSuffix(" s")
        self.duration_spin.setToolTip("0 = unlimited (never stops).")

        self.loop_chk = QCheckBox("Loop")
        self.loop_chk.setChecked(False)

        self.track_chk = QCheckBox("Track duration")
        self.track_chk.setChecked(False)
        self.track_chk.setToolTip("File mode only: transmit for the track length (ffprobe).")

        # Buttons
        self.btn_start = QPushButton("Start")
        self.btn_stop = QPushButton("Stop")
        self.btn_restart = QPushButton("Restart")

        grid = QGridLayout()
        r = 0
        grid.addWidget(self.serial_label, r, 0, 1, 2); r += 1
        grid.addWidget(self.status_label, r, 0, 1, 2); r += 1

        grid.addWidget(QLabel("Pluto URI:"), r, 0)
        grid.addWidget(self.uri_edit, r, 1); r += 1

        grid.addWidget(QLabel("Frequency:"), r, 0)
        grid.addWidget(self.freq_combo, r, 1); r += 1

        grid.addWidget(QLabel("Gain:"), r, 0)
        grid.addWidget(self.gain_spin, r, 1); r += 1

        grid.addWidget(QLabel("Mode:"), r, 0)
        mode_row = QHBoxLayout()
        mode_row.setContentsMargins(0, 0, 0, 0)
        mode_row.addWidget(self.rb_random)
        mode_row.addWidget(self.rb_file)
        mode_row.addWidget(self.rb_record)
        wmode = QWidget()
        wmode.setLayout(mode_row)
        grid.addWidget(wmode, r, 1); r += 1

        # File row
        self.file_row = QWidget()
        file_row_l = QHBoxLayout()
        file_row_l.setContentsMargins(0, 0, 0, 0)
        file_row_l.addWidget(self.file_label, 1)
        file_row_l.addWidget(self.btn_browse, 0)
        self.file_row.setLayout(file_row_l)
        grid.addWidget(self.file_row, r, 0, 1, 2); r += 1

        # IQ row (record mode only)
        self.iq_row = QWidget()
        iq_row_l = QHBoxLayout()
        iq_row_l.setContentsMargins(0, 0, 0, 0)
        iq_row_l.addWidget(self.iq_label, 1)
        iq_row_l.addWidget(self.btn_iq_save, 0)
        self.iq_row.setLayout(iq_row_l)
        grid.addWidget(self.iq_row, r, 0, 1, 2); r += 1

        grid.addWidget(QLabel("Label:"), r, 0)
        grid.addWidget(self.label_edit, r, 1); r += 1

        grid.addWidget(QLabel("Bitrate:"), r, 0)
        grid.addWidget(self.bitrate_spin, r, 1); r += 1

        grid.addWidget(QLabel("Duration:"), r, 0)
        dur_row = QHBoxLayout()
        dur_row.setContentsMargins(0, 0, 0, 0)
        dur_row.addWidget(self.duration_spin)
        dur_row.addWidget(self.loop_chk)
        dur_row.addWidget(self.track_chk)
        wdur = QWidget()
        wdur.setLayout(dur_row)
        grid.addWidget(wdur, r, 1); r += 1

        btn_row = QHBoxLayout()
        btn_row.addWidget(self.btn_start)
        btn_row.addWidget(self.btn_restart)
        btn_row.addWidget(self.btn_stop)
        wbtn = QWidget()
        wbtn.setLayout(btn_row)
        grid.addWidget(wbtn, r, 0, 1, 2); r += 1

        self.setLayout(grid)

        # Signals
        self.rb_random.toggled.connect(self._on_mode_change)
        self.rb_file.toggled.connect(self._on_mode_change)
        self.rb_record.toggled.connect(self._on_mode_change)
        self.btn_browse.clicked.connect(self._browse_file)
        self.btn_iq_save.clicked.connect(self._browse_iq_output)
        self.loop_chk.toggled.connect(self._on_loop_toggle)
        self.track_chk.toggled.connect(self._on_track_toggle)

        self._on_mode_change()

    def _on_mode_change(self):
        """Show / enable only the widgets that apply to the selected mode."""
        is_file = self.rb_file.isChecked()
        is_record = self.rb_record.isChecked()
        is_file_like = is_file or is_record

        self.file_row.setVisible(is_file_like)
        self.iq_row.setVisible(is_record)

        # No Pluto needed in record mode
        self.uri_edit.setEnabled(not is_record)

        # Record mode is offline: no loop or duration
        self.loop_chk.setEnabled(not is_record)
        self.track_chk.setEnabled(not is_record)
        self.duration_spin.setEnabled(not is_record)

        if is_record:
            self.loop_chk.setChecked(False)
            self.track_chk.setChecked(False)
            self.duration_spin.setValue(0)
        else:
            if not self.loop_chk.isChecked() and not self.track_chk.isChecked():
                self.duration_spin.setEnabled(True)

        self.track_chk.setVisible(is_file)

        if not is_file:
            self.track_chk.setChecked(False)

    def _on_loop_toggle(self, checked: bool):
        """Loop and track duration exclude each other; loop means no fixed duration."""
        if self.rb_record.isChecked():
            return

        if checked:
            self.track_chk.setChecked(False)
            self.duration_spin.setValue(0)
            self.duration_spin.setEnabled(False)
        else:
            if not self.track_chk.isChecked():
                self.duration_spin.setEnabled(True)
            if self.duration_spin.value() == 0:
                self.duration_spin.setValue(15)

    def _on_track_toggle(self, checked: bool):
        """Track duration: transmit for the length of the audio file (File mode)."""
        if self.rb_record.isChecked():
            return

        if checked:
            self.loop_chk.setChecked(False)
            self.duration_spin.setEnabled(False)
            self.duration_spin.setValue(0)
        else:
            if not self.loop_chk.isChecked():
                self.duration_spin.setEnabled(True)
            if self.duration_spin.value() == 0:
                self.duration_spin.setValue(15)

    def _browse_file(self):
        fp, _ = QFileDialog.getOpenFileName(
            self, "Select Audio", "",
            "Audio (*.mp3 *.wav *.flac *.aac *.m4a *.ogg);;All (*.*)"
        )
        if fp:
            self.file_label.setText(f"File: {fp}")
            self.file_label.setToolTip(fp)

    def _browse_iq_output(self):
        fp, _ = QFileDialog.getSaveFileName(
            self, "Save IQ File", "",
            "IQ (*.cf32 *.iq);;All (*.*)"
        )
        if fp:
            self.iq_label.setText(f"IQ Output: {fp}")
            self.iq_label.setToolTip(fp)

    def set_device(self, serial: str):
        self.serial_label.setText(f"Serial: {serial}")

    def set_status(self, running: bool):
        if running:
            self.status_label.setText("Status: RUNNING")
            self.status_label.setStyleSheet("font-weight: 800; color: #22c55e;")
        else:
            self.status_label.setText("Status: STOPPED")
            self.status_label.setStyleSheet("font-weight: 800; color: #ef4444;")

    def _current_uri(self) -> str:
        return (self.uri_edit.text() or "").strip()

    def build_config(self) -> TxSlotConfig:
        """Collect the current GUI settings into a TxSlotConfig."""
        preset_key = self.freq_combo.currentText()
        freq_hz = PRESETS_HZ[preset_key]
        gain_db = float(self.gain_spin.value())

        if self.rb_record.isChecked():
            mode = "record"
        elif self.rb_file.isChecked():
            mode = "file"
        else:
            mode = "random"

        audio_path = ""
        txt = self.file_label.text()
        if txt.startswith("File: "):
            audio_path = txt.replace("File: ", "").strip()

        iq_output_path = ""
        iq_txt = self.iq_label.text()
        if iq_txt.startswith("IQ Output: "):
            iq_output_path = iq_txt.replace("IQ Output: ", "").strip()

        # record: duration=-1 | loop: duration=0, loop=1
        # track duration: duration=-1, loop=0 | manual: duration=spin, loop=0
        if mode == "record":
            loop = 0
            duration_s = -1
        elif self.loop_chk.isChecked():
            loop = 1
            duration_s = 0
        elif self.track_chk.isChecked() and mode == "file":
            loop = 0
            duration_s = -1
        else:
            loop = 0
            duration_s = int(self.duration_spin.value())

        return TxSlotConfig(
            uri=self._current_uri(),
            freq_hz=freq_hz,
            gain_db=gain_db,
            mode=mode,
            audio_path=audio_path,
            iq_output_path=iq_output_path,
            label=self.label_edit.text().strip() or "MediComm-DAB",
            bitrate=int(self.bitrate_spin.value()),
            sr=48000,
            ch=2,
            loop=loop,
            duration_s=duration_s,
        )


class MainWindow(QWidget):
    """Main window: one TX card and the log of the running script."""

    def __init__(self, tx_manager, signals: UiSignals, plutos_found=None):
        super().__init__()
        self.tx_manager = tx_manager
        self.signals = signals

        self.setWindowTitle("DAB TX GUI (Pluto)")

        root = QVBoxLayout()

        self.card = TxCard("TX-1", signals)
        root.addWidget(self.card)

        self.log = QTextEdit()
        self.log.setReadOnly(True)
        root.addWidget(self.log)

        self.setLayout(root)
        self.resize(820, 720)

        self.signals.log_line.connect(self._on_log)

        self.card.btn_start.clicked.connect(self._on_start)
        self.card.btn_stop.clicked.connect(self._on_stop)
        self.card.btn_restart.clicked.connect(self._on_restart)

        self.card.set_device("UNKNOWN")
        self._refresh_status()

    def _on_log(self, slot: str, line: str):
        self.log.append(f"[{slot}] {line}")

    def _refresh_status(self):
        running = self.tx_manager.is_running(self.card.slot_name)
        self.card.set_status(running)

    def _on_start(self):
        cfg = self.card.build_config()
        self.tx_manager.start(self.card.slot_name, cfg)
        self._refresh_status()

    def _on_stop(self):
        self.tx_manager.stop(self.card.slot_name)
        self._refresh_status()

    def _on_restart(self):
        cfg = self.card.build_config()
        self.tx_manager.restart(self.card.slot_name, cfg)
        self._refresh_status()
