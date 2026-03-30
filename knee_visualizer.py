"""
Knee Angle Visualizer

Live mode:
  python knee_visualizer.py --port COM6

Simulation mode:
  python knee_visualizer.py

Requires:
  pip install pygame PyOpenGL PyOpenGL_accelerate pyserial

Controls:
  Left-click + drag  - orbit camera
  Scroll wheel       - zoom in / out
  R                  - reset camera
  Q / ESC            - quit
"""

import argparse
import math
import re
import sys
import threading
import time

import pygame
from pygame.locals import *
from OpenGL.GL import *
from OpenGL.GLU import *

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None


MASTER_LINE_RE = re.compile(
    r"IMU_MASTER:\[\s*([+-]?\d+(?:\.\d+)?)\] deg \| "
    r"IMU_SLAVE:\[\s*([+-]?\d+(?:\.\d+)?)\] deg \| "
    r"KNEE_ANGLE:\[\s*([+-]?\d+(?:\.\d+)?)\] deg \| "
    r"ZERO:([A-Z]+)\s*\| BLE:([A-Z]+)"
)


class SimulatedFeed:
    def __init__(self):
        self.t0 = time.time()

    def read(self):
        t = time.time() - self.t0
        freq = 0.28
        thigh_angle = 35.0 + 20.0 * math.sin(2 * math.pi * freq * 0.5 * t)
        shank_angle = 90.0 + 3.0 * math.sin(2 * math.pi * freq * 0.15 * t)
        knee_angle = abs(shank_angle - thigh_angle)
        return {
            "thigh_angle": thigh_angle,
            "shank_angle": shank_angle,
            "knee_angle": knee_angle,
            "zeroed": False,
            "ble_state": "SIM",
            "connected": True,
            "source": "simulation",
        }


class SerialKneeFeed:
    def __init__(self, port, baudrate):
        if serial is None:
            raise RuntimeError("pyserial is not installed. Run: pip install pyserial")

        self.port = port
        self.baudrate = baudrate
        self._lock = threading.Lock()
        self._latest = {
            "thigh_angle": 0.0,
            "shank_angle": 0.0,
            "knee_angle": 0.0,
            "zeroed": False,
            "ble_state": "INIT",
            "connected": False,
            "source": "serial",
        }
        self._serial = serial.Serial(port, baudrate=baudrate, timeout=0.1)
        self._thread = threading.Thread(target=self._reader_loop, daemon=True)
        self._thread.start()

    def _reader_loop(self):
        while True:
            try:
                line = self._serial.readline().decode("utf-8", errors="ignore").strip()
            except serial.SerialException:
                with self._lock:
                    self._latest["connected"] = False
                    self._latest["ble_state"] = "DISC"
                time.sleep(0.25)
                continue

            if not line:
                continue

            match = MASTER_LINE_RE.search(line)
            if not match:
                continue

            thigh_angle, shank_angle, knee_angle, zero_state, ble_state = match.groups()
            with self._lock:
                self._latest = {
                    "thigh_angle": float(thigh_angle),
                    "shank_angle": float(shank_angle),
                    "knee_angle": float(knee_angle),
                    "zeroed": zero_state == "YES",
                    "ble_state": ble_state,
                    "connected": True,
                    "source": self.port,
                }

    def read(self):
        with self._lock:
            return dict(self._latest)


def list_ports():
    if serial is None:
        return []
    return [port.device for port in serial.tools.list_ports.comports()]


def draw_segment(length, width, depth, colour_top, colour_side):
    w, h, d = width, length, depth
    faces = [
        (colour_top, [(w, h, d), (-w, h, d), (-w, 0, d), (w, 0, d)]),
        (colour_top, [(w, 0, -d), (-w, 0, -d), (-w, h, -d), (w, h, -d)]),
        (colour_side, [(w, h, d), (w, 0, d), (w, 0, -d), (w, h, -d)]),
        (colour_side, [(-w, 0, d), (-w, h, d), (-w, h, -d), (-w, 0, -d)]),
        (colour_top, [(w, h, d), (w, h, -d), (-w, h, -d), (-w, h, d)]),
        (colour_side, [(w, 0, -d), (w, 0, d), (-w, 0, d), (-w, 0, -d)]),
    ]
    glBegin(GL_QUADS)
    for col, verts in faces:
        glColor4fv(col)
        for vertex in verts:
            glVertex3fv(vertex)
    glEnd()


def draw_joint_sphere(radius, colour):
    glColor4fv(colour)
    quad = gluNewQuadric()
    gluSphere(quad, radius, 16, 16)
    gluDeleteQuadric(quad)


def draw_angle_arc(angle_deg, radius=0.55):
    if abs(angle_deg) < 0.5:
        return
    steps = 40
    intensity = min(abs(angle_deg) / 90.0, 1.0)
    glLineWidth(3.0)
    glColor4f(intensity, 1.0 - intensity * 0.5, 0.1, 0.85)
    glBegin(GL_LINE_STRIP)
    for i in range(steps + 1):
        angle = (abs(angle_deg) * math.pi / 180.0) * i / steps
        glVertex3f(radius * math.cos(angle), radius * math.sin(angle), 0.02)
    glEnd()
    glLineWidth(1.0)


def draw_hud(font, big_font, data, cam_az, cam_el, zoom, width, height):
    overlay = pygame.Surface((width, height), pygame.SRCALPHA)
    title = font.render("Knee Visualizer", True, (210, 220, 210))
    overlay.blit(title, (20, 14))

    source_text = font.render(f"Source: {data['source']}", True, (140, 160, 170))
    overlay.blit(source_text, (20, 40))

    knee_angle = data["knee_angle"]
    knee_colour = (
        (80, 220, 80)
        if knee_angle < 20
        else (240, 200, 50)
        if knee_angle < 60
        else (220, 80, 80)
    )
    knee_surface = big_font.render(f"{knee_angle:.1f} deg", True, knee_colour)
    overlay.blit(knee_surface, (width // 2 - knee_surface.get_width() // 2, 14))

    lines = [
        (f"Thigh angle {data['thigh_angle']:+7.2f} deg", (180, 140, 255)),
        (f"Shank angle {data['shank_angle']:+7.2f} deg", (100, 200, 255)),
        (f"Knee  angle {data['knee_angle']:+7.2f} deg", (230, 180, 80)),
        (f"BLE {data['ble_state']:<4}   Zeroed {'YES' if data['zeroed'] else 'NO'}", (180, 180, 180)),
    ]
    for index, (text, colour) in enumerate(lines):
        surface = font.render(text, True, colour)
        overlay.blit(surface, (20, height - 92 + index * 24))

    hint = font.render("drag: orbit   scroll: zoom   R: reset", True, (90, 90, 90))
    overlay.blit(hint, (width - hint.get_width() - 16, height - 30))

    cam_text = font.render(f"az {cam_az:+.0f}  el {cam_el:+.0f}  zoom {zoom:.1f}x", True, (130, 130, 130))
    overlay.blit(cam_text, (20, height - 30))
    return overlay


THIGH_LEN = 1.8
SHANK_LEN = 1.7
SEG_W = 0.18
SEG_D = 0.14
JOINT_R = 0.22

THIGH_TOP = (0.55, 0.35, 0.85, 1.0)
THIGH_SIDE = (0.40, 0.25, 0.65, 1.0)
SHANK_TOP = (0.25, 0.55, 0.75, 1.0)
SHANK_SIDE = (0.18, 0.40, 0.58, 1.0)
JOINT_COL = (0.90, 0.70, 0.25, 1.0)

DEFAULT_AZ = 25.0
DEFAULT_EL = 20.0
DEFAULT_ZOOM = 1.0
BASE_DIST = 7.0


def build_feed(args):
    if args.port:
        return SerialKneeFeed(args.port, args.baud)
    return SimulatedFeed()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", help="Serial port for the master board, for example COM6")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate")
    parser.add_argument("--list-ports", action="store_true", help="List detected serial ports and exit")
    args = parser.parse_args()

    if args.list_ports:
        for port in list_ports():
            print(port)
        return

    feed = build_feed(args)

    pygame.init()
    width, height = 960, 680
    pygame.display.set_caption("Knee Angle Visualizer")
    pygame.display.set_mode((width, height), DOUBLEBUF | OPENGL | RESIZABLE)

    font = pygame.font.SysFont("monospace", 17, bold=True)
    big_font = pygame.font.SysFont("monospace", 44, bold=True)

    glEnable(GL_DEPTH_TEST)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glClearColor(0.09, 0.10, 0.12, 1.0)

    cam_az = DEFAULT_AZ
    cam_el = DEFAULT_EL
    cam_zoom = DEFAULT_ZOOM
    dragging = False
    last_mouse = (0, 0)

    clock = pygame.time.Clock()
    center_x = THIGH_LEN / 2.0
    center_y = 0.0
    center_z = 0.0

    while True:
        for event in pygame.event.get():
            if event.type == QUIT:
                pygame.quit()
                sys.exit()

            if event.type == KEYDOWN:
                if event.key in (K_q, K_ESCAPE):
                    pygame.quit()
                    sys.exit()
                if event.key == K_r:
                    cam_az, cam_el, cam_zoom = DEFAULT_AZ, DEFAULT_EL, DEFAULT_ZOOM

            if event.type == MOUSEBUTTONDOWN:
                if event.button == 1:
                    dragging = True
                    last_mouse = event.pos
                elif event.button == 4:
                    cam_zoom = max(0.2, cam_zoom * 0.9)
                elif event.button == 5:
                    cam_zoom = min(8.0, cam_zoom * 1.1)

            if event.type == MOUSEBUTTONUP and event.button == 1:
                dragging = False

            if event.type == MOUSEMOTION and dragging:
                dx = event.pos[0] - last_mouse[0]
                dy = event.pos[1] - last_mouse[1]
                cam_az += dx * 0.4
                cam_el -= dy * 0.4
                cam_el = max(-89, min(89, cam_el))
                last_mouse = event.pos

            if event.type == VIDEORESIZE:
                width, height = event.w, event.h
                glViewport(0, 0, width, height)

        data = feed.read()
        thigh_angle = data["thigh_angle"]
        shank_angle = data["shank_angle"]
        knee_angle = data["knee_angle"]

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()
        gluPerspective(45, width / height, 0.1, 100.0)

        distance = BASE_DIST / cam_zoom
        azimuth_rad = math.radians(cam_az)
        elevation_rad = math.radians(cam_el)
        eye_x = center_x + distance * math.cos(elevation_rad) * math.sin(azimuth_rad)
        eye_y = center_y + distance * math.sin(elevation_rad)
        eye_z = center_z + distance * math.cos(elevation_rad) * math.cos(azimuth_rad)

        glMatrixMode(GL_MODELVIEW)
        glLoadIdentity()
        gluLookAt(eye_x, eye_y, eye_z, center_x, center_y, center_z, 0, 1, 0)

        glPushMatrix()
        glRotatef(-90, 0, 0, 1)
        glRotatef(thigh_angle, 1, 0, 0)

        draw_joint_sphere(JOINT_R * 1.1, JOINT_COL)
        draw_segment(THIGH_LEN, SEG_W, SEG_D, THIGH_TOP, THIGH_SIDE)

        glTranslatef(0, THIGH_LEN, 0)
        draw_joint_sphere(JOINT_R, JOINT_COL)
        draw_angle_arc(knee_angle)

        glRotatef(shank_angle - thigh_angle, 1, 0, 0)
        draw_segment(SHANK_LEN, SEG_W * 0.88, SEG_D * 0.88, SHANK_TOP, SHANK_SIDE)

        glTranslatef(0, SHANK_LEN, 0)
        draw_joint_sphere(JOINT_R * 0.85, JOINT_COL)
        glPopMatrix()

        hud = draw_hud(font, big_font, data, cam_az, cam_el, cam_zoom, width, height)
        hud_data = pygame.image.tostring(hud, "RGBA", True)

        glMatrixMode(GL_PROJECTION)
        glPushMatrix()
        glLoadIdentity()
        glOrtho(0, width, 0, height, -1, 1)
        glMatrixMode(GL_MODELVIEW)
        glPushMatrix()
        glLoadIdentity()
        glDisable(GL_DEPTH_TEST)
        glRasterPos2i(0, 0)
        glDrawPixels(width, height, GL_RGBA, GL_UNSIGNED_BYTE, hud_data)
        glEnable(GL_DEPTH_TEST)
        glPopMatrix()
        glMatrixMode(GL_PROJECTION)
        glPopMatrix()
        glMatrixMode(GL_MODELVIEW)

        pygame.display.flip()
        clock.tick(60)


if __name__ == "__main__":
    main()
