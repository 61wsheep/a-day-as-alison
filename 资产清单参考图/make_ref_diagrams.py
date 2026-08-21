# -*- coding: utf-8 -*-
"""生成美工资产清单的中文教学参考图：
1. 47 格自动瓦片功能布局图（blob-47，Godot 4 "Match Corners and Sides"）
2. 角色行走图 spritesheet 规范图（4方向×4帧）
3. UI 九宫格（9-slice）面板示意图
4. AI 美术生产管线流程图
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.executable).parent.parent.parent))
from daimon_runtime import setup_plot
setup_plot()

import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, FancyArrowPatch
import numpy as np

OUT = Path(__file__).parent

FILLED = "#e0455a"   # 红 = 同地形
EMPTY = "#ffffff"
CENTER = "#3a7d44"   # 绿 = 当前块

# ---------------------------------------------------------------------------
# 图1：47 格自动瓦片
# ---------------------------------------------------------------------------
def valid_blob47():
    """枚举 blob-47 的全部合法掩码。位: N,E,S,W,NW,NE,SW,SE"""
    res = []
    for n in (0, 1):
        for e in (0, 1):
            for s in (0, 1):
                for w in (0, 1):
                    for nw in (0, 1):
                        for ne in (0, 1):
                            for sw in (0, 1):
                                for se in (0, 1):
                                    if nw and not (n and w): continue
                                    if ne and not (n and e): continue
                                    if sw and not (s and w): continue
                                    if se and not (s and e): continue
                                    res.append(dict(N=n, E=e, S=s, W=w, NW=nw, NE=ne, SW=sw, SE=se))
    return res

def category(m):
    edges = m["N"] + m["E"] + m["S"] + m["W"]
    corners = m["NW"] + m["NE"] + m["SW"] + m["SE"]
    if edges == 4 and corners == 4: return "中心块(全包围)"
    if edges == 4: return f"内角 ×{4 - corners}".replace("×0", "") or "中心"
    if edges == 3: return "T 形(一边开口)"
    if edges == 2:
        if (m["N"] and m["S"]) or (m["E"] and m["W"]): return "直通道"
        return "外角(两条邻边)"
    if edges == 1: return "半岛(单边连接)"
    return "孤岛(无连接)"

def draw_tile(ax, x, y, m, scale=1.0):
    pos = {"NW": (0, 2), "N": (1, 2), "NE": (2, 2),
           "W": (0, 1), "C": (1, 1), "E": (2, 1),
           "SW": (0, 0), "S": (1, 0), "SE": (2, 0)}
    for key, (cx, cy) in pos.items():
        if key == "C":
            color = CENTER
        else:
            color = FILLED if m.get(key, 0) else EMPTY
        ax.add_patch(Rectangle((x + cx * scale, y + cy * scale), scale, scale,
                               facecolor=color, edgecolor="#888888", linewidth=0.5))

tiles = valid_blob47()
assert len(tiles) == 47, len(tiles)

# 排序：按功能分组展示
def sort_key(m):
    order = {"中心块(全包围)": 0, "内角": 1, "T 形(一边开口)": 2, "直通道": 3,
             "外角(两条邻边)": 4, "半岛(单边连接)": 5, "孤岛(无连接)": 6}
    return (order.get(category(m), 9) if not category(m).startswith("内角") else 1,
            -(m["N"] + m["E"] + m["S"] + m["W"]),
            -(m["NW"] + m["NE"] + m["SW"] + m["SE"]))
tiles.sort(key=sort_key)

cols = 12
rows = 4
fig, ax = plt.subplots(figsize=(15, 6.2))
for i, m in enumerate(tiles):
    gx, gy = i % cols, rows - 1 - i // cols
    x, y = gx * 4.2, gy * 4.6
    draw_tile(ax, x, y, m)
    cat = category(m)
    label = cat if not cat.startswith("内角") else cat
    ax.text(x + 1.5, y - 0.55, label, ha="center", va="top", fontsize=8.5)
    ax.text(x + 1.5, y + 3.35, f"#{i+1:02d}", ha="center", va="bottom",
            fontsize=7, color="#666666")
ax.set_xlim(-0.5, cols * 4.2)
ax.set_ylim(-1.4, rows * 4.6 + 0.8)
ax.set_aspect("equal")
ax.axis("off")
ax.set_title("47 格自动瓦片功能布局（blob-47 · Godot 4 地形模式 Match Corners and Sides）\n"
             "绿=当前绘制的块  红=相邻同地形  白=相邻异地形/空  "
             "交付时按此 12×4 网格排布为一张 spritesheet（32px/格 → 384×128）",
             fontsize=11)
fig.savefig(OUT / "ref_47tile_layout_cn.png", bbox_inches="tight", dpi=110)
plt.close(fig)

# ---------------------------------------------------------------------------
# 图2：角色行走图 spritesheet 规范
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(11, 6.5))
W, H = 32, 64          # 单帧 32×64（1×2 格）
frames = ["帧1 站立", "帧2 迈左腿", "帧3 站立", "帧4 迈右腿"]
dirs = ["向下 ↓", "向左 ←", "向右 →", "向上 ↑"]
for r, d in enumerate(dirs):
    for c in range(4):
        x, y = c * (W + 6), (3 - r) * (H + 10)
        ax.add_patch(Rectangle((x, y), W, H, facecolor="#f2e8d5",
                               edgecolor="#5a4a3a", linewidth=1.2))
        # 小人示意：头+身
        ax.add_patch(Rectangle((x + 9, y + 40), 14, 16, facecolor="#c9a06a",
                               edgecolor="none"))
        ax.add_patch(Rectangle((x + 8, y + 14), 16, 26, facecolor="#7a9cc6",
                               edgecolor="none"))
        # 底部中心枢轴点
        ax.plot(x + W / 2, y, marker="^", color="#e0455a", markersize=7)
    ax.text(-6, y + H / 2, d, ha="right", va="center", fontsize=12)
for c, f in enumerate(frames):
    ax.text(c * (W + 6) + W / 2, 4 * (H + 10) - 4, f, ha="center",
            va="bottom", fontsize=10)
ax.plot([], [])
ax.set_xlim(-52, 4 * (W + 6) + 8)
ax.set_ylim(-14, 4 * (H + 10) + 16)
ax.set_aspect("equal")
ax.axis("off")
ax.set_title("角色行走图 spritesheet 规范（RPG Maker 惯例 · 4 方向 × 4 帧）\n"
             "单帧 32×64 px（1 格宽 × 2 格高）· 整表 4 行 × 4 列 · 每帧等宽等高 · "
             "枢轴点（▲）在每帧底边中心 · 整表尺寸 128×256 px（不含间距）",
             fontsize=11)
fig.savefig(OUT / "ref_character_spritesheet_cn.png", bbox_inches="tight", dpi=110)
plt.close(fig)

# ---------------------------------------------------------------------------
# 图3：UI 九宫格（9-slice）
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(10, 5.6))
ox, oy, cw, ch = 1.0, 1.0, 2.2, 1.6
labels = {(-1, 1): "左上角\n固定", (0, 1): "上边\n横向拉伸", (1, 1): "右上角\n固定",
          (-1, 0): "左边\n纵向拉伸", (0, 0): "中心\n横纵拉伸", (1, 0): "右边\n纵向拉伸",
          (-1, -1): "左下角\n固定", (0, -1): "下边\n横向拉伸", (1, -1): "右下角\n固定"}
colors = {-1: "#f5c16c", 0: "#e08a4c", 1: "#c05a3a"}
for (gx, gy), text in labels.items():
    w = cw * (0.8 if gx else 1.4)
    h = ch * (0.7 if gy else 1.2)
    x = ox + (0 if gx == -1 else (cw * 0.8 if gx == 0 else cw * 0.8 + cw * 1.4))
    y = oy + (ch * 1.2 + ch * 0.7 if gy == 1 else (ch * 0.7 if gy == 0 else 0))
    ax.add_patch(Rectangle((x, y), w, h, facecolor=colors[gy],
                           edgecolor="#5a4a3a", linewidth=1.2, alpha=0.85))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=9.5)
ax.set_xlim(0, 8.4)
ax.set_ylim(0.4, 5.4)
ax.set_aspect("equal")
ax.axis("off")
ax.set_title("UI 面板九宫格（9-slice）切割规范\n"
             "四角固定不拉伸 · 四边单向拉伸 · 中心自由拉伸 → 一张小底图适配任意尺寸窗口\n"
             "交付要求：在图上标出切割线位置（或注明边距像素值），Godot StyleBoxTexture 直接填边距",
             fontsize=11)
fig.savefig(OUT / "ref_ninepatch_cn.png", bbox_inches="tight", dpi=110)
plt.close(fig)

# ---------------------------------------------------------------------------
# 图4：AI 美术生产管线
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(13, 4.6))
steps = [
    ("① 风格基准", "确定色板/分辨率/视角\n产出 1 张风格样板图\n+ 风格关键词模板"),
    ("② AI 生成", "同一参考图 + 同 seed\n动画帧一次生成整表\n（避免逐帧风格漂移）"),
    ("③ 人工修整", "去背 / 统一调色板\n叠图检查轮廓一致性\n修掉 AI 瑕疵"),
    ("④ 规格化", "对齐像素网格与尺寸\n按命名规范导出 PNG\n按 12×4 / 4×4 排表"),
    ("⑤ 引擎验收", "导入 Godot 实测\n动画循环 / 拼接无缝\n不合格退回 ③"),
]
for i, (t, d) in enumerate(steps):
    x = i * 2.9
    ax.add_patch(Rectangle((x, 1.2), 2.4, 2.2, facecolor="#eef3ee",
                           edgecolor="#3a7d44", linewidth=1.5))
    ax.text(x + 1.2, 3.0, t, ha="center", va="center", fontsize=12, weight="bold")
    ax.text(x + 1.2, 2.0, d, ha="center", va="center", fontsize=8.8)
    if i < 4:
        ax.add_patch(FancyArrowPatch((x + 2.42, 2.3), (x + 2.88, 2.3),
                                     arrowstyle="-|>", mutation_scale=18,
                                     color="#3a7d44", linewidth=2))
ax.set_xlim(-0.2, 14.6)
ax.set_ylim(0.8, 4.0)
ax.axis("off")
ax.set_title("AI 辅助美术生产管线（AI 出稿 ≠ 成品，③④ 是质量的决定环节）", fontsize=12)
fig.savefig(OUT / "ref_ai_pipeline_cn.png", bbox_inches="tight", dpi=110)
plt.close(fig)

print("done:", [p.name for p in OUT.glob("ref_*_cn.png")])
