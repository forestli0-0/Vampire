"""
GIF转PNG精灵表工具
将8向动画GIF文件转换为PNG精灵表

使用方法：
    python convert_gif_to_spritesheet.py

依赖：
    pip install Pillow
"""

import os
from PIL import Image

def gif_to_spritesheet(gif_path, output_path, frame_size=64):
    """将GIF转换为水平排列的PNG精灵表"""
    try:
        gif = Image.open(gif_path)
    except Exception as e:
        print(f"无法打开 {gif_path}: {e}")
        return False
    
    frames = []
    try:
        while True:
            # 转换为RGBA确保透明度正确
            frame = gif.copy().convert('RGBA')
            frames.append(frame)
            gif.seek(gif.tell() + 1)
    except EOFError:
        pass
    
    if not frames:
        print(f"没有找到帧: {gif_path}")
        return False
    
    # 获取帧尺寸
    frame_w, frame_h = frames[0].size
    num_frames = len(frames)
    
    # 创建水平精灵表
    sheet_width = frame_w * num_frames
    sheet_height = frame_h
    spritesheet = Image.new('RGBA', (sheet_width, sheet_height), (0, 0, 0, 0))
    
    for i, frame in enumerate(frames):
        spritesheet.paste(frame, (i * frame_w, 0))
    
    # 保存
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    spritesheet.save(output_path, 'PNG')
    print(f"已转换: {gif_path} -> {output_path} ({num_frames}帧, {frame_w}x{frame_h})")
    return True

def convert_all():
    """转换所有玩家动画GIF"""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    player_dir = os.path.join(base_dir, 'assets', 'characters', 'player')
    
    # 方向映射（按长度降序排列，避免短字符串先匹配）
    dir_patterns = [
        ('north-east', 'north-east'),
        ('north-west', 'north-west'),
        ('south-east', 'south-east'),
        ('south-west', 'south-west'),
        ('north', 'north'),
        ('south', 'south'),
        ('east', 'east'),
        ('west', 'west'),
    ]
    
    def find_direction(filename):
        """从文件名中查找方向"""
        filename_lower = filename.lower()
        for pattern, dir_name in dir_patterns:
            # 使用下划线或连字符分隔的精确匹配
            if f'_{pattern}.' in filename_lower or f'_{pattern}_' in filename_lower or filename_lower.endswith(f'_{pattern}.gif'):
                return dir_name
        return None
    
    # 转换跑步动画
    run_dir = os.path.join(player_dir, '跑步')
    if os.path.exists(run_dir):
        for filename in os.listdir(run_dir):
            if filename.endswith('.gif'):
                direction = find_direction(filename)
                if direction:
                    output_name = f"run_{direction}.png"
                    output_path = os.path.join(player_dir, output_name)
                    gif_path = os.path.join(run_dir, filename)
                    gif_to_spritesheet(gif_path, output_path)
    
    # 转换滑行动画
    slide_dir = os.path.join(player_dir, '滑行')
    if os.path.exists(slide_dir):
        for filename in os.listdir(slide_dir):
            if filename.endswith('.gif'):
                direction = find_direction(filename)
                if direction:
                    output_name = f"slide_{direction}.png"
                    output_path = os.path.join(player_dir, output_name)
                    gif_path = os.path.join(slide_dir, filename)
                    gif_to_spritesheet(gif_path, output_path)
    
    # 转换待机动画
    idle_dir = os.path.join(player_dir, '待机')
    if os.path.exists(idle_dir):
        for filename in os.listdir(idle_dir):
            if filename.endswith('.gif'):
                direction = find_direction(filename)
                if direction:
                    output_name = f"idle_{direction}.png"
                    output_path = os.path.join(player_dir, output_name)
                    gif_path = os.path.join(idle_dir, filename)
                    gif_to_spritesheet(gif_path, output_path)

if __name__ == '__main__':
    print("开始转换GIF到PNG精灵表...")
    convert_all()
    print("转换完成!")
