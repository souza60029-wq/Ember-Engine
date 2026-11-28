extends RefCounted

# Barra de especial. Não desenha nada.
# A barra vale 100 (100%): um estoque = 20, até 5 estoques.
# Todo ganho sai 20% mais rápido (ganho x 1,2). Custos do JSON antigo (100 por estoque) valem x0,2.
# Meia barra (10) é o custo do contra-ataque (Guard Cancel).
# A marca do meio na tela é só visual.

# A barra de especial vale 100 (100%): 5 estoques de 20. Custos e ganhos antigos (100 por estoque)
# são convertidos por ESCALA_LEGADO.
const ESTOQUE: float = 20.0
const ESCALA_LEGADO: float = 0.2
const ESTOQUES_MAX: int = 5
const MULTIPLICADOR_GANHO: float = 1.2
const MEIA_BARRA: float = 10.0

var valor: float = 0.0
var maximo: float = ESTOQUE * ESTOQUES_MAX


func _init(p_maximo: float = ESTOQUE * ESTOQUES_MAX) -> void:
	maximo = p_maximo


func ganhar(q: float) -> void:
	valor = minf(maximo, valor + q * MULTIPLICADOR_GANHO)


func gastar(q: float) -> bool:
	if valor < q:
		return false
	valor -= q
	return true


# Vai de 0 a 5. Na tela, 5 aparece como "MAX".
func estoques_disponiveis() -> int:
	return mini(ESTOQUES_MAX, int(floor(valor / ESTOQUE)))


# Custo de barra de um golpe, já na escala de 100.
static func custo_do_golpe(g: Dictionary) -> float:
	return float(g["custo"]) * ESCALA_LEGADO
