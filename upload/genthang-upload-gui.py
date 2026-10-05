#!/usr/bin/env python3
"""Compact GTK frontend for the Gen Thang ROM uploader."""

import glob
import os
import re
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402


ROM_LIMIT = 4 * 1024 * 1024
FLASH_LIMIT = 8 * 1024 * 1024
PROGRESS_RE = re.compile(r"Uploading:\s+(\d+)/(\d+) bytes \((\d+)%\)")
INVALID_FAT_CHARS = '/\\:*?"<>|'


def serial_ports():
    ports = []
    targets = set()
    patterns = ("/dev/serial/by-id/*SIPEED*", "/dev/ttyUSB*", "/dev/ttyACM*")
    for pattern in patterns:
        for port in sorted(glob.glob(pattern)):
            target = os.path.realpath(port)
            if target not in targets:
                ports.append(port)
                targets.add(target)
    return ports


class UploadWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Gen Thang Uploader")
        self.set_default_size(620, 390)
        self.set_resizable(True)
        self.set_border_width(0)
        self.connect("delete-event", self.on_close)
        self.process = None
        self.output_buffer = ""
        self.last_directory = str(Path.home())
        self.build_ui()
        self.refresh_ports()

    def build_ui(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(b"""
            window, .root { background: #171914; color: #e8eadf; }
            label { color: #e8eadf; font: 13px Sans; }
            .title { color: #f1c75b; font: bold 24px Monospace; }
            .subtitle { color: #8e9781; font: 11px Monospace; }
            .status { color: #aeb7a3; font: 12px Monospace; }
            entry, combobox button {
                background: #22261f;
                border: 1px solid #4a5142;
                border-radius: 3px;
                color: #f3f4ec;
                min-height: 30px;
            }
            entry:focus, combobox button:focus { border-color: #d8ad3f; }
            button {
                background: #30372b;
                border: 1px solid #606b55;
                border-radius: 3px;
                color: #f3f4ec;
                min-height: 30px;
                padding: 2px 12px;
            }
            button:hover { background: #3c4535; border-color: #d8ad3f; }
            button:disabled { color: #73796d; border-color: #3b4036; }
            progressbar trough {
                background: #22261f;
                border: 1px solid #4a5142;
                border-radius: 3px;
                min-height: 24px;
            }
            progressbar progress { background: #b58f32; }
            progressbar text { color: #f3f4ec; font: 12px Monospace; }
            separator { background: #3a4033; }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        root.get_style_context().add_class("root")
        root.set_border_width(22)
        self.add(root)

        title = Gtk.Label(label="Gen Thang Uploader", xalign=0)
        title.get_style_context().add_class("title")
        subtitle = Gtk.Label(label="ROM + CORE TRANSFER CONSOLE", xalign=0)
        subtitle.get_style_context().add_class("subtitle")
        root.pack_start(title, False, False, 0)
        root.pack_start(subtitle, False, False, 0)
        root.pack_start(Gtk.Separator(), False, False, 2)

        grid = Gtk.Grid(column_spacing=14, row_spacing=11)
        grid.set_hexpand(True)
        root.pack_start(grid, True, True, 0)

        self.type_combo = Gtk.ComboBoxText()
        self.type_combo.append("rom", "Game ROM (card root)")
        self.type_combo.append("core", "Core flash image (/cores)")
        self.type_combo.set_active_id("rom")
        self.type_combo.connect("changed", self.type_changed)
        self.attach_row(grid, 0, "Type", self.type_combo)

        self.file_entry = Gtk.Entry(hexpand=True)
        self.file_entry.set_placeholder_text("Select a .md, .bin, or .gen ROM")
        self.file_entry.connect("changed", self.file_changed)
        file_box = Gtk.Box(spacing=7)
        file_box.pack_start(self.file_entry, True, True, 0)
        browse = self.icon_button("document-open-symbolic", "Choose ROM")
        browse.connect("clicked", self.choose_file)
        file_box.pack_start(browse, False, False, 0)
        self.attach_row(grid, 1, "File", file_box)

        self.name_entry = Gtk.Entry(hexpand=True)
        self.name_entry.set_placeholder_text("Filename on TF card")
        self.attach_row(grid, 2, "Card name", self.name_entry)

        device_box = Gtk.Box(spacing=7)
        self.port_combo = Gtk.ComboBoxText(hexpand=True)
        device_box.pack_start(self.port_combo, True, True, 0)
        refresh = self.icon_button("view-refresh-symbolic", "Refresh devices")
        refresh.connect("clicked", self.refresh_ports)
        device_box.pack_start(refresh, False, False, 0)
        self.attach_row(grid, 3, "Device", device_box)

        self.baud_combo = Gtk.ComboBoxText()
        self.baud_combo.append("460800", "460800 (Sipeed debugger)")
        self.baud_combo.append("115200", "115200")
        self.baud_combo.set_active_id("460800")
        self.attach_row(grid, 4, "Baud", self.baud_combo)

        self.progress = Gtk.ProgressBar(show_text=True)
        self.progress.set_text("0%")
        root.pack_start(self.progress, False, False, 0)

        bottom = Gtk.Box(spacing=12)
        self.status = Gtk.Label(label="Ready", xalign=0, hexpand=True, ellipsize=3)
        self.status.set_selectable(True)
        self.status.get_style_context().add_class("status")
        self.upload_button = Gtk.Button.new_with_label("Upload")
        self.upload_button.set_image(Gtk.Image.new_from_icon_name("go-up-symbolic", Gtk.IconSize.BUTTON))
        self.upload_button.set_always_show_image(True)
        self.upload_button.connect("clicked", self.start_upload)
        bottom.pack_start(self.status, True, True, 0)
        bottom.pack_end(self.upload_button, False, False, 0)
        root.pack_start(bottom, False, False, 0)

        targets = Gtk.TargetEntry.new("text/uri-list", 0, 0)
        self.drag_dest_set(Gtk.DestDefaults.ALL, [targets], Gdk.DragAction.COPY)
        self.connect("drag-data-received", self.file_dropped)

    @staticmethod
    def attach_row(grid, row, text, widget):
        label = Gtk.Label(label=text, xalign=1)
        grid.attach(label, 0, row, 1, 1)
        grid.attach(widget, 1, row, 1, 1)

    @staticmethod
    def icon_button(icon, tooltip):
        button = Gtk.Button()
        button.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON))
        button.set_tooltip_text(tooltip)
        return button

    def choose_file(self, _button):
        dialog = Gtk.FileChooserDialog(
            title=("Choose core flash image"
                   if self.type_combo.get_active_id() == "core"
                   else "Choose Mega Drive ROM"),
            parent=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        dialog.add_buttons(
            "Cancel", Gtk.ResponseType.CANCEL,
            "Open", Gtk.ResponseType.OK,
        )
        file_filter = Gtk.FileFilter()
        if self.type_combo.get_active_id() == "core":
            file_filter.set_name("Complete flash images")
            file_filter.add_pattern("*.bin")
        else:
            file_filter.set_name("Mega Drive ROMs")
            for pattern in ("*.md", "*.bin", "*.gen"):
                file_filter.add_pattern(pattern)
        dialog.add_filter(file_filter)
        dialog.set_current_folder(self.last_directory)
        if dialog.run() == Gtk.ResponseType.OK:
            path = dialog.get_filename()
            self.last_directory = str(Path(path).parent)
            self.file_entry.set_text(path)
        dialog.destroy()

    def file_changed(self, entry):
        path = entry.get_text().strip()
        if path:
            self.name_entry.set_text(Path(path).name)

    def type_changed(self, combo):
        core = combo.get_active_id() == "core"
        self.file_entry.set_placeholder_text(
            "Select a complete *_flash.bin image" if core else "Select a .md, .bin, or .gen ROM"
        )
        self.status.set_text("Uploads to /cores (created automatically)" if core else "Ready")

    def refresh_ports(self, _button=None):
        selected = self.port_combo.get_active_id()
        self.port_combo.remove_all()
        ports = serial_ports()
        for port in ports:
            target = os.path.realpath(port)
            label = f"{port}  ->  {target}" if os.path.islink(port) else port
            self.port_combo.append(port, label)
        if selected in ports:
            self.port_combo.set_active_id(selected)
        elif ports:
            self.port_combo.set_active(0)
        else:
            self.port_combo.append("", "No serial device found")
            self.port_combo.set_active(0)
        self.status.set_text("Ready" if ports else "Connect the Sipeed USB debugger")

    def validate(self):
        source = self.file_entry.get_text().strip()
        port = self.port_combo.get_active_id()
        name = self.name_entry.get_text().strip()
        core_image = self.type_combo.get_active_id() == "core"
        if not source or not os.path.isfile(source):
            raise ValueError("Choose an existing ROM file")
        limit = FLASH_LIMIT if core_image else ROM_LIMIT
        if os.path.getsize(source) > limit:
            raise ValueError(f"File exceeds the {limit // (1024 * 1024)} MB limit")
        if not port or not os.path.exists(port):
            raise ValueError("Connect or refresh the serial device")
        if not os.access(port, os.R_OK | os.W_OK):
            raise ValueError(f"No permission for {os.path.realpath(port)}; grant an ACL or join dialout")
        if not name:
            raise ValueError("Enter a card filename")
        try:
            name.encode("ascii")
        except UnicodeEncodeError as error:
            raise ValueError("Card filename must be ASCII") from error
        if any(char in name for char in INVALID_FAT_CHARS):
            raise ValueError("Card filename contains a FAT-invalid character")
        if core_image and not name.lower().endswith(".bin"):
            raise ValueError("Core image filename must end in .bin")
        return source, port, name, core_image

    def start_upload(self, _button):
        try:
            source, port, name, core_image = self.validate()
        except ValueError as error:
            self.message(Gtk.MessageType.WARNING, "Cannot upload", str(error))
            return

        uploader = str(Path(__file__).with_name("genthang-upload"))
        argv = [
            sys.executable,
            uploader,
            port,
            source,
            "--name",
            name,
            "--baud",
            self.baud_combo.get_active_id(),
        ]
        if core_image:
            argv.append("--core")
        self.output_buffer = ""
        self.progress.set_fraction(0)
        self.progress.set_text("0%")
        self.set_busy(True)
        self.status.set_text(f"Connecting to {os.path.realpath(port)}")
        try:
            self.process = Gio.Subprocess.new(
                argv,
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE,
            )
        except GLib.Error as error:
            self.set_busy(False)
            self.message(Gtk.MessageType.ERROR, "Cannot start uploader", error.message)
            return
        self.read_chunk()
        self.process.wait_async(None, self.upload_finished)

    def read_chunk(self):
        if not self.process:
            return
        stream = self.process.get_stdout_pipe()
        stream.read_bytes_async(4096, GLib.PRIORITY_DEFAULT, None, self.chunk_ready)

    def chunk_ready(self, stream, result):
        try:
            data = stream.read_bytes_finish(result).get_data()
        except GLib.Error as error:
            self.output_buffer += f"\n{error.message}"
            return
        if not data:
            return
        text = data.decode("utf-8", "replace")
        self.output_buffer = (self.output_buffer + text)[-4096:]
        matches = list(PROGRESS_RE.finditer(self.output_buffer))
        if matches:
            match = matches[-1]
            percent = int(match.group(3))
            self.progress.set_fraction(percent / 100)
            self.progress.set_text(f"{percent}%")
            self.status.set_text(f"Uploading {int(match.group(1)) / 1048576:.1f} MiB")
        self.read_chunk()

    def upload_finished(self, process, result):
        try:
            process.wait_finish(result)
            success = process.get_successful()
        except GLib.Error as error:
            success = False
            self.output_buffer += f"\n{error.message}"
        self.set_busy(False)
        if success:
            self.progress.set_fraction(1)
            self.progress.set_text("100%")
            self.status.set_text("Upload complete")
            detail = ("Core image installed in /cores. Select Switch core on the device."
                      if self.type_combo.get_active_id() == "core"
                      else "ROM installed on the TF card.")
            self.message(Gtk.MessageType.INFO, "Upload complete", detail)
        else:
            lines = self.output_buffer.replace("\r", "\n").strip().splitlines()
            detail = lines[-1] if lines else "Uploader failed"
            detail = detail.removeprefix("genthang-upload: ")
            self.progress.set_fraction(0)
            self.progress.set_text("0%")
            self.status.set_text(detail)
            self.message(Gtk.MessageType.ERROR, "Upload failed", detail)
        self.process = None

    def set_busy(self, busy):
        for widget in (
            self.file_entry,
            self.name_entry,
            self.type_combo,
            self.port_combo,
            self.baud_combo,
            self.upload_button,
        ):
            widget.set_sensitive(not busy)

    def file_dropped(self, _widget, _context, _x, _y, selection, _info, _time):
        uris = selection.get_uris()
        if len(uris) == 1:
            path, _host = GLib.filename_from_uri(uris[0])
            self.file_entry.set_text(path)

    def message(self, kind, title, detail):
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=kind,
            buttons=Gtk.ButtonsType.OK,
            text=title,
        )
        dialog.format_secondary_text(detail)
        dialog.run()
        dialog.destroy()

    def on_close(self, _window, event):
        if self.process:
            dialog = Gtk.MessageDialog(
                transient_for=self,
                modal=True,
                message_type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.YES_NO,
                text="Stop the active upload?",
            )
            response = dialog.run()
            dialog.destroy()
            if response != Gtk.ResponseType.YES:
                return True
            self.process.force_exit()
        Gtk.main_quit()
        return False


def main():
    window = UploadWindow()
    window.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())