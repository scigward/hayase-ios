#!/bin/bash

# Generate required app icon sizes
sips -z 29 29     AppIcon.png --out AppIcon-App-29x29.png
sips -z 40 40     AppIcon.png --out AppIcon-App-40x40.png
sips -z 60 60     AppIcon.png --out AppIcon-App-60x60.png
sips -z 76 76     AppIcon.png --out AppIcon-App-76x76.png
sips -z 83.5 83.5 AppIcon.png --out AppIcon-App-83.5x83.5.png
sips -z 120 120   AppIcon.png --out AppIcon-App-120x120.png
sips -z 180 180   AppIcon.png --out AppIcon-App-180x180.png
sips -z 1024 1024 AppIcon.png --out AppIcon-ios-marketing-1024x1024.png
