#!/usr/bin/env python3
"""
应用图标生成脚本
将SVG图标转换为不同平台所需的PNG格式图标
"""

import os
import subprocess
from pathlib import Path

def generate_android_icons():
    """生成Android平台图标"""
    svg_path = "assets/icons/app_icon.svg"
    android_res_path = "android/app/src/main/res"
    
    # Android图标尺寸配置
    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192
    }
    
    for folder, size in android_sizes.items():
        output_dir = f"{android_res_path}/{folder}"
        os.makedirs(output_dir, exist_ok=True)
        output_path = f"{output_dir}/ic_launcher.png"
        
        # 使用ImageMagick convert命令转换SVG到PNG
        try:
            subprocess.run([
                "magick", "convert",
                "-background", "transparent",
                "-size", f"{size}x{size}",
                svg_path,
                output_path
            ], check=True)
            print(f"Generated: {output_path}")
        except subprocess.CalledProcessError:
            print(f"Failed to generate {output_path}")
        except FileNotFoundError:
            print("ImageMagick not found. Please install ImageMagick first.")
            return False
    
    return True

def generate_web_icons():
    """生成Web平台图标"""
    svg_path = "assets/icons/app_icon.svg"
    web_path = "web/icons"
    
    # Web图标尺寸配置
    web_sizes = {
        "Icon-192.png": 192,
        "Icon-512.png": 512,
        "Icon-maskable-192.png": 192,
        "Icon-maskable-512.png": 512
    }
    
    os.makedirs(web_path, exist_ok=True)
    
    for filename, size in web_sizes.items():
        output_path = f"{web_path}/{filename}"
        
        try:
            subprocess.run([
                "magick", "convert",
                "-background", "transparent",
                "-size", f"{size}x{size}",
                svg_path,
                output_path
            ], check=True)
            print(f"Generated: {output_path}")
        except subprocess.CalledProcessError:
            print(f"Failed to generate {output_path}")
        except FileNotFoundError:
            print("ImageMagick not found. Please install ImageMagick first.")
            return False
    
    return True

def generate_windows_icons():
    """生成Windows平台图标"""
    svg_path = "assets/icons/app_icon.svg"
    windows_path = "windows/runner/resources"
    
    # Windows图标尺寸配置
    windows_sizes = {
        "app_icon.ico": [16, 32, 48, 64, 128, 256]  # ICO文件包含多个尺寸
    }
    
    os.makedirs(windows_path, exist_ok=True)
    
    # 生成ICO文件（包含多个尺寸）
    output_path = f"{windows_path}/app_icon.ico"
    
    try:
        # 先生成各个尺寸的PNG文件
        temp_files = []
        for size in windows_sizes["app_icon.ico"]:
            temp_file = f"temp_{size}.png"
            subprocess.run([
                "magick", "convert",
                "-background", "transparent",
                "-size", f"{size}x{size}",
                svg_path,
                temp_file
            ], check=True)
            temp_files.append(temp_file)
        
        # 将所有PNG文件合并为ICO文件
        subprocess.run([
            "magick", "convert"
        ] + temp_files + [output_path], check=True)
        
        # 清理临时文件
        for temp_file in temp_files:
            if os.path.exists(temp_file):
                os.remove(temp_file)
        
        print(f"Generated: {output_path}")
        return True
        
    except subprocess.CalledProcessError:
        print(f"Failed to generate {output_path}")
        # 清理临时文件
        for temp_file in temp_files:
            if os.path.exists(temp_file):
                os.remove(temp_file)
        return False
    except FileNotFoundError:
        print("ImageMagick not found. Please install ImageMagick first.")
        return False

def main():
    """主函数"""
    print("开始生成应用图标...")
    
    # 检查SVG文件是否存在
    if not os.path.exists("assets/icons/app_icon.svg"):
        print("错误: 找不到SVG图标文件")
        return
    
    # 生成Android图标
    print("\n生成Android图标...")
    if generate_android_icons():
        print("Android图标生成完成")
    
    # 生成Web图标
    print("\n生成Web图标...")
    if generate_web_icons():
        print("Web图标生成完成")
    
    # 生成Windows图标
    print("\n生成Windows图标...")
    if generate_windows_icons():
        print("Windows图标生成完成")
    
    print("\n图标生成完成!")
    print("\n注意: 如果没有安装ImageMagick，请先安装:")
    print("Windows: 下载并安装 https://imagemagick.org/script/download.php#windows")
    print("macOS: brew install imagemagick")
    print("Linux: sudo apt-get install imagemagick")

if __name__ == "__main__":
    main()