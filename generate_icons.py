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
    
    print("\n图标生成完成!")
    print("\n注意: 如果没有安装ImageMagick，请先安装:")
    print("Windows: 下载并安装 https://imagemagick.org/script/download.php#windows")
    print("macOS: brew install imagemagick")
    print("Linux: sudo apt-get install imagemagick")

if __name__ == "__main__":
    main()