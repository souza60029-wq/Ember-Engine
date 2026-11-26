extends RefCounted

# Regras de um lutador: estados, física, golpes e combo.
# Não desenha nada e não lê arquivos.
# Pulo: decolagem no chão (4 frames no normal, 2 na sombra). A direção é escolhida
# na decolagem e fica travada até cair. Sem controle aéreo.
# Escala: corpo e hitbox crescem; velocidade e altura do pulo ficam em px.

const Barra = preload("res://engine/nucleo/Barra.gd")
const Formato = preload("res://engine/formato/Formato.gd")

enum Estado { PARADO, ANDANDO, PULANDO, DEFENDENDO, ATACANDO, GOLPEADO, CAIDO, LEVANTANDO, ESQUIVANDO, KO, DECOLANDO, PARRY, GUARDA_QUEBRADA }

const NOMES_ESTADO := ["PARADO", "ANDANDO", "PULANDO", "DEFENDENDO", "ATACANDO", "GOLPEADO", "CAIDO", "LEVANTANDO", "ESQUIVANDO", "KO", "DECOLANDO", "PARRY", "GUARDA_QUEBRADA"]
const DT: float = 1.0 / 60.0
# Todos os pulos: 20% mais baixos e 20% mais curtos no ar. Com o mesmo impulso (v), gravidade x1,25:
# altura = v^2 / (2g) cai 20% e tempo no ar = 2v / g também cai 20%.
const GRAVIDADE: float = 2300.0 * 1.25

# Velocidade inicial do pulo (px/s; negativo sobe). Sombra: 25% acima do normal.
const VEL_NORMAL_ALTO: float = -1090.0
const VEL_NORMAL_BAIXO: float = -800.0
const VEL_SOMBRA_ALTO: float = -1360.0
const VEL_SOMBRA_BAIXO: float = -1000.0
# Frames de decolagem no chão antes de sair do chão.
const DECOLAGEM_NORMAL: int = 4
const DECOLAGEM_SOMBRA: int = 2

const VEL_ANDAR: float = 400.0
const CHAO_Y: float = 480.0
const LIMITE_ESQ: float = 90.0
const LIMITE_DIR: float = 870.0
# Blow Off: o oponente é arremessado para longe (ARREMESSO_DISTANCIA). Se ele estiver na metade da tela
# em direção à qual está sendo jogado (perto da parede), é arremessado contra a parede.
const TELA_LARGURA: float = 960.0
const ARREMESSO_FRAMES: int = 36
const ARREMESSO_DISTANCIA: float = 280.0
const VIDA_MAX: float = 1000.0
const HITSTUN: int = 18
const HITSTUN_BLOWBACK: int = 20
const BLOQUEIO: int = 10
const CAIDO_FRAMES: int = 36
const CAIDO_BLOWOFF: int = 90
const LEVANTAR_FRAMES: int = 18
# Esquiva: distância fixa para todos (22 frames x 330 px/s = 121 px), sem custo.
# Para frente atravessa o oponente; com o direcional para trás, rola para trás.
const ESQUIVA_FRAMES: int = 22
const ESQUIVA_VEL: float = 520.0
const ESQUIVA_RECARGA: int = 20
const CUSTO_LEVANTAR: float = 25.0

# Just defense (parry): apertar para trás logo antes do golpe encostar.
# Segurar para trás desde antes é defesa normal. Janela de 5 frames (~83 ms).
const JANELA_PARRY: int = 5
const PARRY_RECARGA: int = 24
const PARRY_FRAMES: int = 14
const PARRY_AVISO: int = 40

# Barra de defesa: cada golpe defendido gasta uma parte. Chegou a zero, a guarda quebra.
const GUARDA_MAX: float = 100.0
const GUARDA_CUSTO := {1: 14.0, 2: 20.0, 3: 28.0}
const GUARDA_QUEBRADA_FRAMES: int = 75
const GUARDA_REGEN_ESPERA: int = 60
const GUARDA_REGEN_POR_FRAME: float = 0.4

# Golpes fortes (força 2 ou 3) causam 30% menos dano.
const FORCA_FORTE: int = 2

# REV (overhead): os dois socos ou os dois chutes executam o golpe forte na hora, sem a parte lenta
# (startup). Cada uso enche a barra PULSE. Ela esvazia sozinha (99 -> 0 em 5 s), mas só depois de
# 2 s sem usar REV. Cheia (100), entra em FLATLINE: o personagem pisca vermelho, perde a defesa
# 15% mais rápido, anda mais devagar e não pode usar REV até o Pulse zerar.
const PULSE_POR_USO: float = 30.0
const PULSE_ESPERA: int = 120
const PULSE_DECAI_FRAME: float = 99.0 / 300.0
const FLATLINE_VEL: float = 0.7
const FLATLINE_GUARDA: float = 1.15
const REV_JANELA_COMBO: int = 4
const REDUCAO_DANO_FORTE: float = 0.30
const CUSTO_GUARD_CANCEL: float = 50.0
const CORPO_LARGURA: float = 50.0
const CORPO_ALTURA: float = 120.0
const ESCALA_MIN: float = 0.5
const ESCALA_MAX: float = 6.0
# Tamanho geral dos personagens (multiplica altura_px). 2.7 deixa o corpo padrão com ~324 px de
# 540 (60%), a proporção do KOF XV. Pulo e velocidades já foram ajustados junto.
const TAMANHO_GERAL: float = 2.7
const JANELA_PULO_SOMBRA: int = 6
const JANELA_COMBO: int = 50
const DIRECAO_SALTO_MIN: float = 0.3

var golpes: Array = []
var barra = Barra.new()
var escala: float = 1.0
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var no_chao: bool = false
var direita: bool = true
var vida: float = VIDA_MAX
var estado: Estado = Estado.PARADO
var tempo: int = 0
var duracao: int = 0
var total_ataque: int = 0
var golpe_atual: Dictionary = {}
var golpe_acertou: bool = false
var combo: int = 0
var janela_combo: int = 0
var dano_combo: float = 0.0
var oponente = null
var bloqueando: bool = false
var bloqueado: bool = false
var caido_recuperavel: bool = true
var arremessado: bool = false  # voando até a parede por um Blow Off (sem atrito no ar)
var carga_tras_t: float = 0.0
var carga_baixo_t: float = 0.0
var frames_desde_baixo: int = 999
var pulo_sombra: bool = false
var pulo_direcao_x: float = 0.0
var guarda: float = GUARDA_MAX
var frames_sem_guarda: int = 0
var parry_janela: int = 0
var parry_trava: int = 0
var parry_aviso: int = 0
var guarda_aviso: int = 0
var esquiva_dir: float = 1.0
var esquiva_trava: int = 0
var reacao: String = "alto"
var relogio: int = 0
var _tras_antes: bool = false
var pulse: float = 0.0
var pulse_ocioso: int = 0
var flatline: bool = false
# --- Ember Forge: dados por frame (boxes, ticks, magia) ---
var forge: Dictionary = {}
var escala_sprite: float = TAMANHO_GERAL
var agachado: bool = false
var ar_tempo: int = 0
var parado_t: int = 0
var defesa_aviso: int = 0
var reacao_nivel: String = "mid"
var _hist: Array = []
var _hist_golpes: Array = []
var _ult_idx_tag: int = -1
# Blocos de golpe: movimento programado, sons por sprite e encadeamento.
var _mov_frames: int = 0
var _mov_vx: float = 0.0
var _cadeia: int = 0
var _ultimo_idx_som: int = -2
# Fila de eventos para a Luta tocar sons: {"tipo": String, "golpe": Dictionary}
var eventos: Array = []


# Dano de um golpe depois da redução dos golpes fortes.
static func dano_do_golpe(g: Dictionary) -> float:
	var d: float = float(g["dano"])
	if int(g["forca"]) >= FORCA_FORTE:
		d *= 1.0 - REDUCAO_DANO_FORTE
	return d

# ---------- Ciclo de vida ----------

func definir_golpes(lista: Array) -> void:
	golpes = []
	for g in lista:
		if typeof(g) == TYPE_DICTIONARY:
			golpes.append(Formato.normalizar_golpe(g))


func definir_forge(f: Dictionary, esc: float) -> void:
	forge = f
	escala = clampf(esc, ESCALA_MIN, ESCALA_MAX)
	escala_sprite = escala


func tem_forge() -> bool:
	return not forge.is_empty()


# Move do Forge que a engine toca agora, com as reservas obrigatórias do formato.
func nome_move() -> String:
	var frente: float = 1.0 if direita else -1.0
	match estado:
		Estado.ATACANDO:
			return str(golpe_atual.get("forge_move", ""))
		Estado.PARADO:
			if agachado:
				return "defesa_agachado" if defesa_aviso > 0 else "agachado"
			if defesa_aviso > 0:
				return "defesa_neutra"
			return "afk" if parado_t > 600 else "parado"
		Estado.ANDANDO:
			return "andando_frente"
		Estado.DEFENDENDO:
			if agachado:
				return "defesa_agachado" if defesa_aviso > 0 else "agachado"
			return "defesa_neutra" if (defesa_aviso > 0 or guarda_aviso > 0) else "andando_costas"
		Estado.DECOLANDO, Estado.PULANDO:
			if pulo_direcao_x * frente > 0.1:
				return "pulando_frente"
			if pulo_direcao_x * frente < -0.1:
				return "pulando_tras"
			return "pulando"
		Estado.GOLPEADO:
			if bloqueado:
				if no_chao:
					return "defesa_aerea"
				if agachado:
					return "defesa_agachado"
				return "defesa_alta" if reacao_nivel == "overhead" else "defesa_neutra"
			return "hit_" + reacao_nivel
		Estado.CAIDO, Estado.KO:
			return "caindo_rolando" if reacao == "rasteira" else "caindo_frente"
		Estado.LEVANTANDO:
			return "levantando_frente"
		Estado.ESQUIVANDO:
			return "backdash" if esquiva_dir * frente < 0.0 else "roll"
		Estado.PARRY:
			return "parry"
		Estado.GUARDA_QUEBRADA:
			return "guarda_quebrada"
	return "parado"


func _move_ok(nome: String) -> Dictionary:
	var m: Dictionary = (forge.get("moves", {}) as Dictionary).get(nome, {})
	return m if not (m.get("frames", []) as Array).is_empty() else {}


func move_resolvido(nome: String) -> Dictionary:
	var cadeia: Array = [nome]
	match nome:
		"defesa_alta":
			cadeia.append("defesa_neutra")
		"defesa_aerea":
			cadeia.append("defesa_agachado")
		"pulando_frente", "pulando_tras":
			cadeia.append("pulando")
		"andando_costas":
			cadeia.append("defesa_neutra")
		"backdash":
			cadeia.append("roll")
		"afk":
			cadeia.append("parado")
	cadeia.append("parado")
	for n in cadeia:
		var m: Dictionary = _move_ok(str(n))
		if not m.is_empty():
			return m
	return {}


# Frame do Forge que está na tela agora (vazio se o personagem não usa o formato novo).
func quadro_forge() -> Dictionary:
	if forge.is_empty():
		return {}
	var m: Dictionary = move_resolvido(nome_move())
	if m.is_empty():
		return {}
	var cron: Array = m["cron"]
	var n: int = cron.size()
	if n == 0:
		return {}
	var t: int = 0
	if estado == Estado.ATACANDO:
		t = tempo - 1
	elif bool(m["loop"]):
		t = relogio % n
	elif estado == Estado.PULANDO or estado == Estado.DECOLANDO:
		t = ar_tempo
	else:
		t = tempo
	return m["frames"][int(cron[clampi(t, 0, n - 1)])]


func _rects_forge(f: Dictionary, tipo: String, origem: Vector2 = Vector2.INF) -> Array:
	var r: Array = []
	if f.is_empty():
		return r
	var o: Vector2 = pos if origem == Vector2.INF else origem
	for b in (f["boxes"] as Dictionary).get(tipo, []):
		var w: float = float(b[2]) * escala_sprite
		var x: float = float(b[0]) * escala_sprite
		r.append(Rect2(o.x + x if direita else o.x - x - w, o.y + float(b[1]) * escala_sprite, w, float(b[3]) * escala_sprite))
	return r


# Onde o personagem pode ser acertado (várias hurtboxes). Sem dados do Forge: o corpo inteiro.
func hurt_rects() -> Array:
	if tem_forge():
		var r: Array = _rects_forge(quadro_forge(), "hurtbox")
		if not r.is_empty():
			return r
	return [corpo_rect()]


# Hitboxes que causam dano agora (só em frames "active" do Forge).
func hit_rects() -> Array:
	if tem_forge() and estado == Estado.ATACANDO:
		var f: Dictionary = quadro_forge()
		if f.is_empty() or str(f["fase"]) != "active":
			return []
		return _rects_forge(f, "hitbox")
	if hitbox_ativa():
		return [hitbox_rect()]
	return []


func armadura_ativa() -> bool:
	return tem_forge() and not _rects_forge(quadro_forge(), "armor").is_empty()


func proxguard_rects() -> Array:
	return _rects_forge(quadro_forge(), "proxguard") if tem_forge() else []


# Solta a magia no frame marcado com a tag "solta".
func _forge_tags() -> void:
	if not tem_forge() or estado != Estado.ATACANDO:
		return
	var m: Dictionary = move_resolvido(nome_move())
	if m.is_empty():
		return
	var cron: Array = m["cron"]
	if cron.is_empty():
		return
	var idx: int = int(cron[clampi(tempo - 1, 0, cron.size() - 1)])
	if idx == _ult_idx_tag:
		return
	_ult_idx_tag = idx
	for t in (m["frames"][idx]["tags"] as Array):
		if str(t["k"]) == "solta":
			eventos.append({"tipo": "projetil_forge", "golpe": golpe_atual, "move": m, "idx": idx, "tag": t})


func _condicoes_ok(g: Dictionary) -> bool:
	for c in g.get("condicoes", []):
		match str(c["k"]):
			"no_ar":
				if not no_chao:
					return false
			"no_chao":
				if no_chao:
					return false
			"agachado":
				if not agachado:
					return false
			"depois_de", "depois_de_acertar":
				var achou: bool = false
				for h in _hist_golpes:
					if str(h["nome"]) == str(c["golpe"]) and relogio - int(h["t"]) <= 70 and (str(c["k"]) == "depois_de" or bool(h["acertou"])):
						achou = true
				if not achou:
					return false
	return true


func _digito_dir(dir: Vector2) -> int:
	var frente: float = 1.0 if direita else -1.0
	var x: int = 1 if dir.x * frente > 0.5 else (-1 if dir.x * frente < -0.5 else 0)
	var y: int = 1 if dir.y > 0.5 else (-1 if dir.y < -0.5 else 0)
	if y == 1:
		return 3 if x == 1 else (1 if x == -1 else 2)
	if y == -1:
		return 9 if x == 1 else (7 if x == -1 else 8)
	return 6 if x == 1 else (4 if x == -1 else 5)


func _casa_dir(d: int, alvo: int) -> bool:
	if d == alvo:
		return true
	match d:
		3:
			return alvo == 2 or alvo == 6
		1:
			return alvo == 2 or alvo == 4
		9:
			return alvo == 8 or alvo == 6
		7:
			return alvo == 8 or alvo == 4
	return false


# Comando de golpe especial, por exemplo "236P" (meia-lua para a frente + soco).
func _comando_ok(cmd: String) -> bool:
	var seq: String = cmd.left(cmd.length() - 1)
	var idx: int = seq.length() - 1
	var i: int = _hist.size() - 1
	var ultimo: int = -1
	var olhou: int = 0
	while i >= 0 and idx >= 0 and olhou < 26:
		if _casa_dir(int(_hist[i]), int(seq[idx])):
			if ultimo < 0:
				ultimo = _hist.size() - 1 - i
			idx -= 1
		i -= 1
		olhou += 1
	return idx < 0 and ultimo <= 10


func definir_escala(e: float) -> void:
	escala = clampf(e, ESCALA_MIN, ESCALA_MAX)


func largura_corpo() -> float:
	return corpo_rect().size.x if tem_forge() else CORPO_LARGURA * escala


func altura_corpo() -> float:
	return CORPO_ALTURA * escala


func resetar(x: float, olhando_direita: bool) -> void:
	pos = Vector2(x, CHAO_Y)
	vel = Vector2.ZERO
	no_chao = false
	direita = olhando_direita
	vida = VIDA_MAX
	barra.valor = 0.0
	combo = 0
	janela_combo = 0
	dano_combo = 0.0
	estado = Estado.PARADO
	tempo = 0
	duracao = 0
	total_ataque = 0
	golpe_atual = {}
	golpe_acertou = false
	bloqueando = false
	bloqueado = false
	caido_recuperavel = true
	arremessado = false
	carga_tras_t = 0.0
	carga_baixo_t = 0.0
	frames_desde_baixo = 999
	pulo_sombra = false
	pulo_direcao_x = 0.0
	guarda = GUARDA_MAX
	frames_sem_guarda = 0
	parry_janela = 0
	parry_trava = 0
	parry_aviso = 0
	guarda_aviso = 0
	esquiva_dir = 1.0
	esquiva_trava = 0
	reacao = "alto"
	relogio = 0
	_tras_antes = false
	_mov_frames = 0
	_cadeia = 0
	_ultimo_idx_som = -2
	pulse = 0.0
	pulse_ocioso = 0
	flatline = false

# ---------- Entrada e estados ----------

func atualizar(dir: Vector2, apertados: Dictionary) -> void:
	relogio += 1
	pulse_ocioso += 1
	if pulse > 0.0 and pulse_ocioso > PULSE_ESPERA:
		pulse = maxf(0.0, pulse - PULSE_DECAI_FRAME)
		if flatline and pulse <= 0.0:
			flatline = false
	if parry_aviso > 0:
		parry_aviso -= 1
	if guarda_aviso > 0:
		guarda_aviso -= 1
	if defesa_aviso > 0:
		defesa_aviso -= 1
	if esquiva_trava > 0:
		esquiva_trava -= 1
	if estado != Estado.GUARDA_QUEBRADA and estado != Estado.KO:
		frames_sem_guarda = mini(frames_sem_guarda + 1, 9999)
		if frames_sem_guarda > GUARDA_REGEN_ESPERA and guarda < GUARDA_MAX:
			guarda = minf(GUARDA_MAX, guarda + GUARDA_REGEN_POR_FRAME)
	if estado == Estado.KO:
		_aplicar_fisica()
		return
	# Vira para o oponente só no chão, em estado livre. No ar a direção fica travada.
	if oponente != null and not no_chao and estado in [Estado.PARADO, Estado.ANDANDO, Estado.DEFENDENDO]:
		direita = oponente.pos.x >= pos.x
	var frente: float = 1.0 if direita else -1.0
	var atras: bool = dir.x * frente < -0.5
	var cima: bool = dir.y < -0.5
	var baixo: bool = dir.y > 0.5
	_hist.append(_digito_dir(dir))
	if _hist.size() > 40:
		_hist.pop_front()
	if estado in [Estado.PARADO, Estado.ANDANDO, Estado.DEFENDENDO]:
		agachado = baixo and not no_chao
	elif estado != Estado.ATACANDO and estado != Estado.GOLPEADO:
		agachado = false
	carga_tras_t = carga_tras_t + DT if atras else 0.0
	carga_baixo_t = carga_baixo_t + DT if baixo else 0.0
	frames_desde_baixo = 0 if baixo else mini(frames_desde_baixo + 1, 999)
	_atualizar_parry(atras and not _tras_antes, atras)
	bloqueando = atras and estado in [Estado.PARADO, Estado.ANDANDO, Estado.PULANDO, Estado.DEFENDENDO, Estado.GOLPEADO]
	match estado:
		Estado.PARADO, Estado.ANDANDO, Estado.PULANDO, Estado.DEFENDENDO:
			_estado_livre(dir, apertados, atras, cima)
		Estado.DECOLANDO:
			_processar_decolagem(dir)
		Estado.ATACANDO:
			_processar_ataque(apertados)
		Estado.GOLPEADO:
			if bloqueado and apertados.get("BO", false) and barra.valor >= CUSTO_GUARD_CANCEL and oponente != null:
				_guard_cancel()
			else:
				_processar_golpeado()
		Estado.CAIDO:
			_processar_caido(apertados)
		Estado.LEVANTANDO, Estado.ESQUIVANDO, Estado.PARRY, Estado.GUARDA_QUEBRADA:
			_processar_temporizado()
	parado_t = parado_t + 1 if (estado == Estado.PARADO and not agachado) else 0
	_aplicar_fisica()


func _estado_livre(dir: Vector2, apertados: Dictionary, atras: bool, cima: bool) -> void:
	if apertados.get("ESQ", false) and not no_chao and esquiva_trava == 0:
		_iniciar_esquiva(dir)
		return
	var rev: String = _rev_pedido(apertados)
	if rev != "" and _tentar_rev(rev):
		return
	var g: Dictionary = _escolher_golpe(apertados)
	if not g.is_empty():
		_executar(g)
		return
	if no_chao:
		# No ar: a direção foi escolhida na decolagem. Sem controle aéreo.
		estado = Estado.PULANDO
		return
	if agachado and not cima:
		estado = Estado.DEFENDENDO if atras else Estado.PARADO
		vel.x = 0.0
		return
	if cima:
		_iniciar_decolagem(dir)
		return
	if atras:
		estado = Estado.DEFENDENDO
		vel.x = dir.x * VEL_ANDAR * 0.5 * _mult_vel()
	elif absf(dir.x) > 0.3:
		estado = Estado.ANDANDO
		vel.x = dir.x * VEL_ANDAR * _mult_vel()
	else:
		estado = Estado.PARADO
		vel.x = 0.0


func _escolher_golpe(apertados: Dictionary) -> Dictionary:
	for g in golpes:
		var cmd: String = str(g.get("comando", ""))
		if cmd == "":
			continue
		var soco: bool = apertados.get("LP", false) or apertados.get("HP", false)
		var chute: bool = apertados.get("LK", false) or apertados.get("HK", false)
		if (cmd.ends_with("P") and soco) or (cmd.ends_with("K") and chute):
			if _comando_ok(cmd) and _condicoes_ok(g) and float(g["custo"]) <= barra.valor and (not g["so_ar"] or no_chao):
				return g
	for g in golpes:
		var d: Dictionary = g
		if str(d.get("comando", "")) != "" or not _condicoes_ok(d):
			continue
		if not apertados.get(d["botao"], false):
			continue
		if not _bloco_do_tipo(d, "comecar_de").is_empty():
			continue
		if d["carga"] == "tras" and carga_tras_t < float(d["carga_seg"]):
			continue
		if d["carga"] == "baixo" and carga_baixo_t < float(d["carga_seg"]):
			continue
		if d["so_ar"] and not no_chao:
			continue
		if float(d["custo"]) > barra.valor:
			continue
		return d
	return {}


func _executar(g: Dictionary, encadeado: bool = false) -> void:
	if not encadeado:
		_cadeia = 0
	_mov_frames = 0
	_ultimo_idx_som = -2
	if str(g["carga"]) != "":
		carga_tras_t = 0.0
		carga_baixo_t = 0.0
	var custo: float = float(g["custo"])
	if custo > 0.0:
		barra.gastar(custo)
	golpe_atual = g.duplicate(true)
	eventos.append({"tipo": "golpe", "golpe": golpe_atual})
	golpe_acertou = false
	_ult_idx_tag = -1
	estado = Estado.ATACANDO
	tempo = 0
	total_ataque = int(g["startup"]) + int(g["active"]) + int(g["recovery"])
	if not no_chao:
		vel.x = 0.0
	_blocos_do_quadro()
	_sons_do_quadro()
	_forge_tags()


func _processar_ataque(apertados: Dictionary) -> void:
	tempo += 1
	if tempo > total_ataque:
		_fim_do_golpe()
		return
	# REV logo depois de começar um golpe (soco fraco e depois o forte) vira o golpe forte na hora.
	if tempo <= REV_JANELA_COMBO:
		var rev: String = _rev_pedido(apertados)
		if rev != "" and _tentar_rev(rev):
			return
	_blocos_do_quadro()
	_sons_do_quadro()
	_forge_tags()
	if _mov_frames > 0:
		vel.x = _mov_vx
		_mov_frames -= 1
	elif not no_chao:
		vel.x = 0.0
	_tentar_encadear(apertados)


func _mult_vel() -> float:
	return FLATLINE_VEL if flatline else 1.0


func _rev_pedido(apertados: Dictionary) -> String:
	if bool(apertados.get("REVP", false)):
		return "P"
	if bool(apertados.get("REVK", false)):
		return "K"
	return ""


# Executa o golpe forte (HP ou HK) direto na parte ativa. Devolve false se não deu.
func _tentar_rev(tipo: String) -> bool:
	if flatline:
		return false
	var botao: String = "HP" if tipo == "P" else "HK"
	var g: Dictionary = {}
	for x in golpes:
		var d: Dictionary = x
		if bool(d["base"]) and str(d["botao"]) == botao:
			g = d
			break
	if g.is_empty() or (bool(g["so_ar"]) and not no_chao):
		return false
	_executar(g)
	var inicio: int = int(g["startup"])
	for t in range(1, inicio + 1):
		tempo = t
		_blocos_do_quadro()
	tempo = inicio
	_sons_do_quadro()
	pulse_ocioso = 0
	pulse = minf(100.0, pulse + PULSE_POR_USO)
	if pulse >= 100.0:
		flatline = true
	eventos.append({"tipo": "rev", "golpe": {}})
	return true


func _bloco_do_tipo(g: Dictionary, tipo: String) -> Dictionary:
	for b in g.get("blocos", []):
		if str((b as Dictionary)["tipo"]) == tipo:
			return b
	return {}


func _golpe_por_nome(nome: String) -> Dictionary:
	for g in golpes:
		if str((g as Dictionary)["nome"]) == nome:
			return g
	return {}


# Blocos que acontecem num frame do golpe: mover, pular, parar e lançar magia.
func _blocos_do_quadro() -> void:
	for b in golpe_atual.get("blocos", []):
		var d: Dictionary = b
		var tipo: String = str(d["tipo"])
		if not d.has("quadro") or int(d["quadro"]) != tempo:
			continue
		match tipo:
			"mover":
				_mov_vx = float(d["vx"]) * (1.0 if direita else -1.0)
				_mov_frames = int(d["frames"])
			"pular":
				vel.y = -absf(float(d["vy"]))
				no_chao = true
			"parar":
				_mov_frames = 0
				vel.x = 0.0
			"projetil":
				eventos.append({"tipo": "projetil", "golpe": golpe_atual, "bloco": d})


# Sons marcados em sprites do golpe: tocam quando o sprite aparece.
func _sons_do_quadro() -> void:
	var sons: Array = golpe_atual.get("sons_quadros", [])
	if sons.is_empty():
		return
	var idx: int = Formato.indice_no_tempo(golpe_atual, tempo)
	if idx == _ultimo_idx_som:
		return
	_ultimo_idx_som = idx
	for s in sons:
		if int((s as Dictionary)["quadro"]) == maxi(idx, 0):
			eventos.append({"tipo": "som_quadro", "golpe": {}, "arquivo": str((s as Dictionary)["arquivo"])})


# Golpe que "começa de outro": a partir do fim do startup, se o botão dele for apertado.
func _tentar_encadear(apertados: Dictionary) -> void:
	if _cadeia >= 6 or tempo < int(golpe_atual["startup"]):
		return
	for g in golpes:
		var d: Dictionary = g
		var b: Dictionary = _bloco_do_tipo(d, "comecar_de")
		if b.is_empty() or str(b["golpe"]) != str(golpe_atual["nome"]):
			continue
		if str(b["quando"]) == "acertar" and not golpe_acertou:
			continue
		if not apertados.get(d["botao"], false):
			continue
		if bool(d["so_ar"]) and not no_chao:
			continue
		if float(d["custo"]) > barra.valor:
			continue
		_cadeia += 1
		_executar(d, true)
		return


# Fim do golpe: bloco "Quando o golpe terminar" (subir ou ir para outro golpe).
func _fim_do_golpe() -> void:
	var g: Dictionary = golpe_atual
	if not g.is_empty():
		_hist_golpes.append({"nome": str(g.get("nome", "")), "acertou": golpe_acertou, "t": relogio})
		if _hist_golpes.size() > 6:
			_hist_golpes.pop_front()
	golpe_atual = {}
	tempo = 0
	_mov_frames = 0
	estado = Estado.PULANDO if no_chao else Estado.PARADO
	var b: Dictionary = _bloco_do_tipo(g, "ao_fim")
	if b.is_empty():
		return
	if str(b["acao"]) == "subir":
		vel.y = -absf(float(b["vy"]))
		no_chao = true
		estado = Estado.PULANDO
		eventos.append({"tipo": "pulo", "golpe": {}})
	elif _cadeia < 6:
		var alvo: Dictionary = _golpe_por_nome(str(b["golpe"]))
		if not alvo.is_empty():
			_cadeia += 1
			_executar(alvo, true)


# Decolagem: começa no chão, sem movimento. Ao fim, decide alto ou baixo pelo cima
# (ainda segurado = alto; já solto = baixo) e sai com a direção escolhida no início.
func _iniciar_decolagem(dir: Vector2) -> void:
	pulo_sombra = frames_desde_baixo <= JANELA_PULO_SOMBRA
	pulo_direcao_x = dir.x if absf(dir.x) > DIRECAO_SALTO_MIN else 0.0
	estado = Estado.DECOLANDO
	tempo = 0
	duracao = DECOLAGEM_SOMBRA if pulo_sombra else DECOLAGEM_NORMAL
	vel = Vector2.ZERO


func _processar_decolagem(dir: Vector2) -> void:
	tempo += 1
	vel.x = 0.0
	if tempo < duracao:
		return
	var alto: bool = dir.y < -0.5
	if pulo_sombra:
		vel.y = VEL_SOMBRA_ALTO if alto else VEL_SOMBRA_BAIXO
	else:
		vel.y = VEL_NORMAL_ALTO if alto else VEL_NORMAL_BAIXO
	vel.x = pulo_direcao_x * VEL_ANDAR * _mult_vel()
	no_chao = true
	eventos.append({"tipo": "pulo", "golpe": {}})
	estado = Estado.PULANDO
	tempo = 0
	duracao = 0


func _iniciar_esquiva(dir: Vector2) -> void:
	var frente: float = 1.0 if direita else -1.0
	esquiva_dir = -frente if dir.x * frente < -0.5 else frente
	esquiva_trava = ESQUIVA_FRAMES + ESQUIVA_RECARGA
	eventos.append({"tipo": "esquiva", "golpe": {}})
	estado = Estado.ESQUIVANDO
	tempo = 0
	duracao = ESQUIVA_FRAMES
	golpe_atual = {}
	bloqueado = false
	vel.x = esquiva_dir * ESQUIVA_VEL


func _processar_temporizado() -> void:
	tempo += 1
	if estado == Estado.ESQUIVANDO:
		vel.x = esquiva_dir * ESQUIVA_VEL
	elif estado == Estado.GUARDA_QUEBRADA:
		vel.x *= 0.85
		guarda = GUARDA_MAX * float(tempo) / float(maxi(1, duracao))
	else:
		vel.x = 0.0
	if tempo >= duracao:
		_voltar_neutro()


func _processar_caido(apertados: Dictionary) -> void:
	tempo += 1
	if not arremessado:
		vel.x *= 0.85
	if caido_recuperavel and apertados.get("ESQ", false) and barra.valor >= CUSTO_LEVANTAR:
		barra.gastar(CUSTO_LEVANTAR)
		estado = Estado.LEVANTANDO
		tempo = 0
		duracao = ESQUIVA_FRAMES
		vel.x = 0.0
		return
	if tempo >= duracao:
		estado = Estado.LEVANTANDO
		tempo = 0
		duracao = LEVANTAR_FRAMES
		vel.x = 0.0


func _processar_golpeado() -> void:
	tempo += 1
	vel.x *= 0.85
	if tempo >= duracao:
		_voltar_neutro()


func _voltar_neutro() -> void:
	estado = Estado.PULANDO if no_chao else Estado.PARADO
	tempo = 0
	duracao = 0
	bloqueado = false
	golpe_atual = {}


# Janela de just defense: abre quando o "trás" é apertado de novo (soltou e apertou).
func _atualizar_parry(tras_novo: bool, atras: bool) -> void:
	_tras_antes = atras
	if parry_trava > 0:
		parry_trava -= 1
	if parry_janela > 0:
		parry_janela -= 1
		if parry_janela == 0:
			parry_trava = PARRY_RECARGA
	elif tras_novo and parry_trava == 0 and estado in [Estado.PARADO, Estado.ANDANDO, Estado.PULANDO, Estado.DEFENDENDO]:
		parry_janela = JANELA_PARRY


func _guard_cancel() -> void:
	barra.gastar(CUSTO_GUARD_CANCEL)
	var sentido: float = 1.0 if oponente.pos.x > pos.x else -1.0
	oponente.receber_blowback(sentido * 300.0)
	_voltar_neutro()

# ---------- Hitbox e colisão (quem decide o acerto é a Luta) ----------

func corpo_rect() -> Rect2:
	if tem_forge():
		var f: Dictionary = quadro_forge()
		var rs: Array = _rects_forge(f, "pushbox")
		if rs.is_empty():
			rs = _rects_forge(f, "hurtbox")
		if not rs.is_empty():
			var u: Rect2 = rs[0]
			for r in rs:
				u = u.merge(r)
			return u
	var w: float = CORPO_LARGURA * escala
	var h: float = altura_corpo()
	return Rect2(pos.x - w * 0.5, pos.y - h, w, h)


func hitbox_ativa() -> bool:
	if estado != Estado.ATACANDO or golpe_atual.is_empty():
		return false
	if tem_forge():
		return not hit_rects().is_empty()
	var inicio: int = int(golpe_atual["startup"])
	var fim: int = inicio + int(golpe_atual["active"])
	return tempo > inicio and tempo <= fim


# Hitbox na escala do personagem. Virado para a esquerda, espelha em relação ao corpo.
func hitbox_rect() -> Rect2:
	if not hitbox_ativa():
		return Rect2()
	var hb: Dictionary = golpe_atual["hitbox"]
	var x_rel: float = float(hb["x"]) * escala
	var w: float = float(hb["w"]) * escala
	var x: float = pos.x + x_rel if direita else pos.x - x_rel - w
	return Rect2(x, pos.y + float(hb["y"]) * escala, w, float(hb["h"]) * escala)


func resultado_para(g: Dictionary) -> String:
	if estado == Estado.ESQUIVANDO or estado == Estado.LEVANTANDO or estado == Estado.KO or estado == Estado.PARRY:
		return "nada"
	var antichao: bool = g["antichao"]
	if estado == Estado.CAIDO:
		return "acerto" if antichao else "nada"
	if antichao:
		return "nada"
	if bloqueando and parry_janela > 0:
		return "parry"
	if bloqueando:
		var nivel: String = str(g.get("nivel", "mid"))
		if nivel == "low" and not agachado and not no_chao:
			return "acerto"
		if nivel == "overhead" and agachado:
			return "acerto"
		return "bloqueio"
	return "acerto"


# Just defense: sem dano, sem gastar a barra de defesa.
func receber_parry(_g: Dictionary) -> void:
	estado = Estado.PARRY
	tempo = 0
	duracao = PARRY_FRAMES
	bloqueado = false
	golpe_atual = {}
	vel.x = 0.0
	parry_janela = 0
	parry_trava = 0
	parry_aviso = PARRY_AVISO
	eventos.append({"tipo": "parry", "golpe": {}})


func _quebrar_guarda() -> void:
	estado = Estado.GUARDA_QUEBRADA
	tempo = 0
	duracao = GUARDA_QUEBRADA_FRAMES
	guarda = 0.0
	bloqueado = false
	golpe_atual = {}
	vel.x = _empurrao_base() * 60.0
	guarda_aviso = PARRY_AVISO
	eventos.append({"tipo": "guarda_quebrada", "golpe": {}})


func receber_bloqueio(g: Dictionary) -> void:
	reacao_nivel = str(g.get("nivel", "mid"))
	frames_sem_guarda = 0
	var custo_guarda: float = float(GUARDA_CUSTO.get(int(g["forca"]), 14.0))
	if flatline:
		custo_guarda *= FLATLINE_GUARDA
	guarda -= custo_guarda
	if guarda <= 0.0:
		_quebrar_guarda()
		return
	eventos.append({"tipo": "bloqueio", "golpe": g})
	estado = Estado.GOLPEADO
	tempo = 0
	duracao = BLOQUEIO
	bloqueado = true
	golpe_atual = {}
	vel.x = _empurrao_base() * 60.0


func receber_acerto(g: Dictionary, dano: float) -> void:
	reacao_nivel = str(g.get("nivel", "mid"))
	var era_caido: bool = estado == Estado.CAIDO
	arremessado = false
	vida = maxf(0.0, vida - dano)
	golpe_atual = {}
	bloqueado = false
	tempo = 0
	if vida <= 0.0:
		estado = Estado.KO
		vel.x = 0.0
		return
	var blowoff: bool = g["blowoff"]
	var knock: bool = era_caido or bool(g["antichao"]) or blowoff or int(g["forca"]) >= 3
	reacao = _classificar_reacao(g, knock)
	eventos.append({"tipo": "acerto", "golpe": g})
	if knock:
		estado = Estado.CAIDO
		duracao = CAIDO_BLOWOFF if blowoff else CAIDO_FRAMES
		caido_recuperavel = not blowoff
		vel.x = 0.0 if era_caido else _empurrao_base() * 120.0
		if blowoff:
			_arremessar()
	else:
		estado = Estado.GOLPEADO
		duracao = HITSTUN
		vel.x = _empurrao_base() * 60.0


# Arremesso do Blow Off. A direção é para longe de quem bateu. Na metade da tela para onde ele está sendo
# jogado (perto da parede), ele vai até a parede; na outra metade, só é jogado ARREMESSO_DISTANCIA.
func _arremessar() -> void:
	var dir: float = _empurrao_base()
	if oponente != null and not is_equal_approx(pos.x, oponente.pos.x):
		dir = 1.0 if pos.x > oponente.pos.x else -1.0
	var meio: float = TELA_LARGURA * 0.5
	var perto_da_parede: bool = (dir > 0.0 and pos.x > meio) or (dir < 0.0 and pos.x < meio)
	var alvo: float
	if perto_da_parede:
		alvo = LIMITE_DIR if dir > 0.0 else LIMITE_ESQ
	else:
		alvo = clampf(pos.x + dir * ARREMESSO_DISTANCIA, LIMITE_ESQ, LIMITE_DIR)
	arremessado = true
	no_chao = true
	vel.x = (alvo - pos.x) / (float(ARREMESSO_FRAMES) * DT)
	vel.y = -GRAVIDADE * DT * float(ARREMESSO_FRAMES + 1) * 0.5


# Onde o golpe pegou, pela altura do centro da hitbox: baixo, medio ou alto.
# Golpe baixo que derruba vira "rasteira".
func _classificar_reacao(g: Dictionary, derrubou: bool) -> String:
	var hb: Dictionary = g["hitbox"]
	var centro: float = -(float(hb["y"]) + float(hb["h"]) * 0.5)
	var rel: float = centro / CORPO_ALTURA
	if rel < 0.35:
		return "rasteira" if derrubou else "baixo"
	if rel < 0.7:
		return "medio"
	return "alto"


# Nome da animação (SLOTS do Formato) para o estado atual. "" = animação do golpe.
func slot_animacao() -> String:
	match estado:
		Estado.PARADO:
			return "parado"
		Estado.ANDANDO:
			return "andando"
		Estado.PULANDO, Estado.DECOLANDO:
			return "pulando"
		Estado.DEFENDENDO:
			return "defendendo"
		Estado.GOLPEADO:
			return "bloqueio" if bloqueado else "golpeado_" + reacao
		Estado.CAIDO:
			return "rasteira" if reacao == "rasteira" else "caido"
		Estado.LEVANTANDO:
			return "levantando"
		Estado.ESQUIVANDO:
			return "esquiva"
		Estado.KO:
			return "ko"
		Estado.PARRY:
			return "parry"
		Estado.GUARDA_QUEBRADA:
			return "guarda_quebrada"
	return ""


func receber_blowback(vx: float) -> void:
	reacao = "medio"
	estado = Estado.GOLPEADO
	tempo = 0
	duracao = HITSTUN_BLOWBACK
	bloqueado = false
	golpe_atual = {}
	vel.x = vx


func _empurrao_base() -> float:
	# Empurra para trás, já que o personagem está virado para o oponente
	return -1.0 if direita else 1.0

# ---------- Física e utilidades ----------

func _aplicar_fisica() -> void:
	if no_chao:
		ar_tempo += 1
		vel.y += GRAVIDADE * DT
	else:
		ar_tempo = 0
	pos += vel * DT
	if pos.y >= CHAO_Y:
		pos.y = CHAO_Y
		if no_chao:
			no_chao = false
			vel.y = 0.0
			if arremessado:
				arremessado = false
				vel.x = 0.0
			# Pouso: deslize horizontal do pulo ou do ataque aéreo para no chão.
			if estado == Estado.PULANDO or estado == Estado.ATACANDO:
				vel.x = 0.0
			if estado == Estado.PULANDO:
				estado = Estado.PARADO
	pos.x = clampf(pos.x, LIMITE_ESQ, LIMITE_DIR)


func nome_estado() -> String:
	return NOMES_ESTADO[estado]