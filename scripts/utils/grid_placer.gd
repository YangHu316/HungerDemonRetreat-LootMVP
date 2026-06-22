class_name GridPlacer
extends RefCounted

# 在 GridInventory 中找第一个能容纳 item 的位置。返回 [x,y,rotated] 或 null。
static func find_first_fit(grid: GridInventory, item: ItemData) -> Variant:
	for rotated in [false, true]:
		var w: int = item.grid_h if rotated else item.grid_w
		var h: int = item.grid_w if rotated else item.grid_h
		for y in range(0, grid.rows - h + 1):
			for x in range(0, grid.cols - w + 1):
				if grid.can_place(item, x, y, rotated):
					return [x, y, rotated]
	return null
