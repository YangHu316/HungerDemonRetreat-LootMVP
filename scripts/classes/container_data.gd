class_name ContainerData
extends Resource

@export_enum("drawer", "cabinet", "safe") var container_type: String = "drawer"
@export var search_time: float = 1.5
@export var grid_cols: int = 2
@export var grid_rows: int = 2
@export var loot_table: ContainerLootTable
