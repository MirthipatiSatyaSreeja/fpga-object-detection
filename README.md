# FPGA-Based Vehicle Object Detection

Real-time vehicle object detection implemented on an **Artix-7 100T FPGA**
using an **OV7670 camera**, FPGA-based neural-network accelerator, and
VGA display.

## Overview

This project implements a real-time vehicle object detection system on an
Artix-7 100T FPGA.

The OV7670 camera captures the image, the FPGA performs image preprocessing
and neural-network based detection, and the result is displayed through VGA.

## Hardware

- Artix-7 100T FPGA development board
- OV7670 camera module
- VGA display
- Camera and VGA interface connections

## System Flow

OV7670 Camera
↓
Image Capture
↓
Image Preprocessing
↓
64 × 64 Image
↓
Q12 Fixed-Point Conversion
↓
Neural-Network Accelerator
↓
Vehicle Detection
↓
VGA Display

## Main Features

- Real-time image capture using OV7670 camera
- FPGA-based image processing
- 64 × 64 image preprocessing
- Q12 fixed-point data processing
- FPGA-based neural-network accelerator
- Vehicle detection
- Detection stabilization
- VGA output at 640 × 480 resolution

## FPGA Implementation

The design is written in Verilog and targets an **Artix-7 100T FPGA**.

The project includes RTL modules for:

- OV7670 camera initialization
- Camera image capture
- Image resizing
- Q12 fixed-point conversion
- Neural-network acceleration
- Detection stabilization
- VGA timing and display
- Vehicle label generation

## Project Structure

```text
fpga-object-detection/
│
├── README.md
│
├── src/
│   └── top.v
│
├── Verilog RTL modules
│
├── Neural-network weights and LUT files
│
└── arty_a7_100t_camera_vga_cnn.xdc
