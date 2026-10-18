extends Node
class_name Human

## 水量
@export
var water_volume: int = 0;

## 食物量
@export
var food_volume: int = 0;

## 居民年龄
@export
var age: int = 0




func tick():
	pass

## 构造函数
func Human(water_volume: int, food_volume: int, age: int):
	self.water_volume = water_volume
	self.food_volume = food_volume
	self.age = age

