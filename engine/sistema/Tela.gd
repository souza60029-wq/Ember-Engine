extends Node

# Suporte a qualquer tela (16:9, widescreen 19.5:9 / 20:9, 4:3 de tablet).
# O projeto usa stretch "canvas_items" + aspect "expand": a área visível cresce para o lado que sobra.
# Todas as telas do Ember desenham numa área base de 960 x 540; aqui ela é centralizada na área
# visível e o que sobra nas bordas é preenchido com o fundo (use Tela.area() para fundos lisos).

const BASE := Vector2(960.0, 540.0)

signal mudou

var margem := Vector2.ZERO   # deslocamento da área base dentro da tela visível
var visivel := BASE          # tamanho da área visível (nunca menor que BASE)
var _alvos: Array = []       # cenas que seguem a margem (WeakRef)


func _ready() -> void:
	get_tree().root.size_changed.connect(_recalcular)
	_recalcular()


func _recalcular() -> void:
	var v: Vector2 = get_tree().root.get_visible_rect().size
	visivel = Vector2(maxf(v.x, BASE.x), maxf(v.y, BASE.y))
	margem = ((visivel - BASE) * 0.5).floor()
	var vivos: Array = []
	for w in _alvos:
		var no: CanvasItem = (w as WeakRef).get_ref() as CanvasItem
		if no != null:
			_posicionar(no)
			vivos.append(w)
	_alvos = vivos
	mudou.emit()


func _posicionar(no: CanvasItem) -> void:
	var c := no as Control
	if c != null:
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.size = BASE
	no.position = margem


# Chame no _ready() de cada tela cheia (Control ou Node2D): ela passa a ficar centralizada.
func ajustar(no: CanvasItem) -> void:
	_posicionar(no)
	_alvos.append(weakref(no))


# Retângulo da tela inteira nas coordenadas da cena ajustada (para fundos lisos que cobrem tudo).
func area() -> Rect2:
	return Rect2(-margem, visivel)


# Posição de um toque (coordenadas da tela visível) nas coordenadas da cena ajustada.
func local(p: Vector2) -> Vector2:
	return p - margem
