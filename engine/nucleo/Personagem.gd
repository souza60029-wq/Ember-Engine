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
const IMPOSING_FRAMES: int = 90
const STUN_FRAMES: int = 90
# Comando padrão dos 4 pulos quando o arquivo não traz "input" (valores de fábrica da Forge).
const PULOS_PADRAO := {
	"normal": {"seq": [8], "botao": "", "janela": 20, "tol": 6},
	"alto": {"seq": [2, 8], "botao": "", "janela": 20, "tol": 6},
	"sombra_baixo": {"seq": [8], "botao": "ESQ", "janela": 20, "tol": 6},
	"sombra_alto": {"seq": [2, 8], "botao": "ESQ", "janela": 20, "tol": 6},
}
# Todas as barras valem 100 (100%). O dano de golpes do .ember vem em % da vida (dano_pct).
# Golpes antigos (personagem.json) guardam o dano numa escala de 1000; DANO_LEGADO converte para %.
const VIDA_MAX: float = 100.0
const DANO_LEGADO: float = 0.1
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

# Quick (QP, QK, QB): executa o golpe forte (HP, HK ou BO) na hora, sem a parte lenta
# (startup). No controle: os dois socos = QP, os dois chutes = QK. Cada uso enche a barra PULSE. Ela esvazia sozinha (99 -> 0 em 5 s), mas só depois de
# 2 s sem usar Quick. Cheia (100), entra em FLATLINE: o personagem pisca vermelho, perde a defesa
# 15% mais rápido, anda mais devagar e não pode usar Quick até o Pulse zerar.
const PULSE_POR_USO: float = 30.0
const PULSE_ESPERA: int = 120
const PULSE_DECAI_FRAME: float = 99.0 / 300.0
const FLATLINE_VEL: float = 0.7
const FLATLINE_GUARDA: float = 1.15
const QUICK_JANELA_COMBO: int = 4
const REDUCAO_DANO_FORTE: float = 0.30
const CUSTO_GUARD_CANCEL: float = 50.0
const CORPO_LARGURA: float = 50.0
const CORPO_ALTURA: float = 120.0
const ESCALA_MIN: float = 0.5
const ESCALA_MAX: float = 6.0
# TAMANHO GERAL dos personagens do formato antigo (multiplica altura_px). Era 2.7; agora 2.0 (cerca de
# 25% menor). Para personagens do .ember o tamanho é EmberForge.ALTURA_ALVO.
const TAMANHO_GERAL: float = 2.0
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
var _modo_arquivo: bool = false     # os golpes têm "input" do .ember: a engine só lê e executa
var _hist_bt: Array = []            # por tick: botões que acabaram de ser apertados
var _bt_antes: Dictionary = {}
var _grav: float = GRAVIDADE        # gravidade do momento (os pulos do arquivo mudam)
var _pulo_atual: String = ""        # normal, alto, sombra_alto ou sombra_baixo (pulos do arquivo)
var _pulo_ticks: int = 0
var _anim_nome: String = ""         # animação do Forge em curso e há quantos ticks ela toca
var _anim_t: int = 0
var _som_nome: String = ""
var _som_idx: int = -1
var _stun: bool = false
var _imposing: bool = false
var _wall: bool = false             # golpe com a prop wall: animação rebatido_parede
var _wall_pousou: bool = false
var _wall_pouso_t: int = 0
var _ricochete: bool = false        # vai bater na parede e voltar
var _ricochete_volta: bool = false  # já está voltando: animação rebatido
var _wall_prox: float = 0.0         # 0 a 1: quão perto da parede estava (altura da volta do ricochete)
var _queda_tras: bool = false
# Cursor de animação dos moves com "parar_se" (andando_*, correndo...): anda frame a frame lendo o analógico.
var _cur_i: int = 0
var _cur_t: int = 0
var _cur_est: Dictionary = {"pass": {}, "dir": {}}
var _cur_fim: bool = false          # a animação terminou (o último frame fica parado)
var _cur_forcar: bool = false       # sair do loop na hora (trocou de movimento ou golpe em nao_quebra)
var _manter: String = ""            # movimento com fases que está tocando o recovery antes de sair
var _pendente: Dictionary = {}      # golpe que espera o recovery do movimento (nao_quebra)
var _pendente_t: int = 0
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
	# .ember: o dano é o valor exato definido na Forge (% da vida), sem redução por força.
	if float(g.get("dano_pct", -1.0)) >= 0.0:
		return float(g["dano_pct"])
	var d: float = float(g["dano"]) * DANO_LEGADO
	if int(g["forca"]) >= FORCA_FORTE:
		d *= 1.0 - REDUCAO_DANO_FORTE
	return d

# ---------- Ciclo de vida ----------

func definir_golpes(lista: Array) -> void:
	golpes = []
	_modo_arquivo = false
	for g in lista:
		if typeof(g) == TYPE_DICTIONARY:
			var n: Dictionary = Formato.normalizar_golpe(g)
			golpes.append(n)
			if not (n["input"] as Dictionary).is_empty():
				_modo_arquivo = true


func definir_forge(f: Dictionary, esc: float) -> void:
	forge = f
	escala = clampf(esc, ESCALA_MIN, ESCALA_MAX)
	escala_sprite = escala


func tem_forge() -> bool:
	return not forge.is_empty()


# Move do Forge que a engine toca agora, com as reservas obrigatórias do formato.
func nome_move() -> String:
	if _manter != "" and (estado == Estado.PARADO or estado == Estado.ANDANDO or estado == Estado.DEFENDENDO):
		return _manter
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
			if _imposing:
				return "caindo_imposing"
			if _stun:
				return "stun"
			return "hit_" + reacao_nivel
		Estado.CAIDO, Estado.KO:
			if _wall:
				return "rebatido_parede"
			if _ricochete_volta:
				return "rebatido"
			if _queda_tras:
				return "caindo_tras"
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


# Índice do frame no tick t do move: passadas com repetições (cron), depois o trecho que repete para
# sempre (cron_loop) ou, se não houver, o último frame fica parado.
static func _idx_cron(m: Dictionary, t: int) -> int:
	var cron: Array = m["cron"]
	var lp: Array = m.get("cron_loop", [])
	if t < cron.size():
		return int(cron[maxi(t, 0)])
	if not lp.is_empty():
		return int(lp[(t - cron.size()) % lp.size()])
	return int(cron[cron.size() - 1])


# Frame do Forge que está na tela agora (vazio se o personagem não usa o formato novo).
func quadro_forge() -> Dictionary:
	if forge.is_empty():
		return {}
	var nome: String = nome_move()
	var m: Dictionary = move_resolvido(nome)
	if m.is_empty():
		return {}
	var cron: Array = m["cron"]
	var n: int = cron.size()
	if n == 0 and (m.get("cron_loop", []) as Array).is_empty():
		return {}
	var frames: Array = m["frames"]
	if bool(m.get("dinamico", false)) and estado != Estado.ATACANDO:
		return frames[clampi(_cur_i if nome == _anim_nome else 0, 0, frames.size() - 1)]
	if _wall and nome == "rebatido_parede":
		var seg: int = _frame_espera(frames, "parede")
		if seg >= 0:
			# Fica no frame "colisao/parede" até bater na parede; espera espera_ms e segue.
			if not _wall_pousou:
				return frames[seg]
			var espera: int = int((frames[seg]["proximo"] as Dictionary).get("espera", 0))
			var depois: int = maxi(_anim_t - _wall_pouso_t, 0)
			if depois < espera:
				return frames[seg]
			var ini: int = 0
			for k in range(seg + 1):
				ini += int(frames[k]["ticks"])
			return frames[_idx_cron(m, ini + depois - espera)]
	var t: int = 0
	if estado == Estado.ATACANDO:
		t = tempo - 1
	elif bool(m["loop"]) and n > 0:
		t = relogio % n
	elif estado == Estado.PULANDO or estado == Estado.DECOLANDO:
		t = ar_tempo
		if _pulo_ticks > 0 and n > 0:
			t = int(float(ar_tempo) / float(_pulo_ticks) * float(n))
	elif bool(m.get("usa_trechos", false)):
		t = _anim_t
	else:
		t = tempo
	return frames[_idx_cron(m, t)]


# Primeiro frame que espera colisão com a parede (animação rebatido_parede), ou -1.
func _frame_espera(frames: Array, sub: String) -> int:
	for k in range(frames.size()):
		var p: Dictionary = frames[k].get("proximo", {})
		if not p.is_empty() and str(p["se"]) == "colisao" and str(p["sub"]) == sub:
			return k
	return -1


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
	var idx: int = _idx_cron(m, maxi(tempo - 1, 0))
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
				if not _depois_de_ok(c):
					return false
	return true


func _eh_golpe(g: Dictionary, nome: String) -> bool:
	return nome != "" and (str(g.get("forge_move", "")) == nome or str(g.get("nome", "")) == nome)


# "Depois de": vale enquanto o golpe anterior toca um frame entre "de" e "ate" (-1 = até o último),
# e por mais "apos_ticks" depois que ele termina. depois_de_acertar exige que o anterior tenha acertado.
func _depois_de_ok(c: Dictionary) -> bool:
	var alvo: String = str(c.get("golpe", ""))
	var acertar: bool = str(c["k"]) == "depois_de_acertar"
	if estado == Estado.ATACANDO and _eh_golpe(golpe_atual, alvo):
		if acertar and not golpe_acertou:
			return false
		var f: Dictionary = quadro_forge()
		var idx: int = int(f.get("i", 0)) if not f.is_empty() else 0
		var ate: int = int(c.get("ate", -1))
		return idx >= int(c.get("de", 0)) and (ate < 0 or idx <= ate)
	for h in _hist_golpes:
		if (str(h["nome"]) == alvo or str(h.get("move", "")) == alvo) and relogio - int(h["t"]) <= int(c.get("apos_ticks", 0)):
			if not acertar or bool(h["acertou"]):
				return true
	return false


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


# Reconhecimento de comando do arquivo: {seq, botao, janela, tol}. Devolve o tamanho da sequência se
# o comando foi cumprido neste tick, ou -1. botao_alt troca o botão (Quick usa a mesma seq com QP/QK/QB).
# O botão pode vir até "tol" ticks antes ou depois do último passo da sequência.
func _casa_input(inp: Dictionary, botao_alt: String = "") -> int:
	var seq: Array = inp.get("seq", [])
	var botao: String = botao_alt if botao_alt != "" else str(inp.get("botao", ""))
	var tol: int = int(inp.get("tol", 6))
	var janela: int = int(inp.get("janela", 24))
	var n: int = _hist.size()
	if n == 0 or (seq.is_empty() and botao == ""):
		return -1
	if seq.is_empty():
		return 0 if bool((_hist_bt[n - 1] as Dictionary).get(botao, false)) else -1
	var ultimo: int = int(seq[seq.size() - 1])
	var ts_min: int = maxi(0, n - 1 - tol) if botao != "" else n - 1
	for ts in range(n - 1, ts_min - 1, -1):
		if not _casa_dir(int(_hist[ts]), ultimo) or not _passos_anteriores(seq, ts, janela):
			continue
		if botao == "":
			return seq.size()
		for tb in range(maxi(0, ts - tol), mini(n - 1, ts + tol) + 1):
			if bool((_hist_bt[tb] as Dictionary).get(botao, false)) and maxi(ts, tb) == n - 1:
				return seq.size()
	return -1


# Passos antes do último, em ordem, dentro da janela. Passo repetido ([4,4]) exige soltar entre os toques.
func _passos_anteriores(seq: Array, ts: int, janela: int) -> bool:
	var q: int = ts
	for k in range(seq.size() - 2, -1, -1):
		var alvo: int = int(seq[k])
		var p: int = q - 1
		var achou: bool = false
		while p >= 0 and ts - p <= janela:
			if _casa_dir(int(_hist[p]), alvo):
				achou = true
				break
			p -= 1
		if not achou:
			return false
		if alvo == int(seq[k + 1]):
			var solto: bool = false
			for x in range(p + 1, q):
				if not _casa_dir(int(_hist[x]), alvo):
					solto = true
			if not solto:
				return false
		q = p
	return true


func _tem_condicao_depois(g: Dictionary) -> bool:
	for c in g.get("condicoes", []):
		if str(c["k"]) == "depois_de" or str(c["k"]) == "depois_de_acertar":
			return true
	return false


# Escolhe o golpe cujo comando do arquivo foi cumprido. Vence a sequência mais longa; com a mesma
# quantidade, o que tem direção ganha do que só tem botão. Devolve {g, quick} ou {}.
func _escolher_golpe_arquivo(apertados: Dictionary, encadeando: bool = false) -> Dictionary:
	var melhor: Dictionary = {}
	var melhor_peso: int = -1
	for x in golpes:
		var d: Dictionary = x
		var inp: Dictionary = d["input"]
		if inp.is_empty() or (encadeando and not _tem_condicao_depois(d)):
			continue
		if not _condicoes_ok(d) or float(d["custo"]) > barra.valor or (bool(d["so_ar"]) and not no_chao):
			continue
		if encadeando and _eh_golpe(golpe_atual, str(d.get("forge_move", ""))):
			continue
		var n: int = _casa_input(inp)
		var rapido: bool = false
		var q: Dictionary = d["quick"]
		if n < 0 and not q.is_empty() and not flatline and bool(apertados.get(str(q["botao"]), false)):
			n = _casa_input(inp, str(q["botao"]))
			rapido = n >= 0
		if n < 0:
			continue
		var peso: int = n * 2 + (1 if n > 0 else 0)
		if peso > melhor_peso:
			melhor_peso = peso
			melhor = {"g": d, "quick": rapido}
	return melhor


# Executa o golpe do arquivo. Por Quick: corta a fase marcada (startup ou recovery) e enche o Pulse.
func _executar_arquivo(sel: Dictionary, encadeado: bool = false) -> void:
	var g: Dictionary = sel["g"]
	_executar(g, encadeado)
	if not bool(sel["quick"]):
		return
	var q: Dictionary = g["quick"]
	if str(q["corta"]) == "startup":
		var inicio: int = int(g["startup"])
		for t in range(1, inicio + 1):
			tempo = t
			_blocos_do_quadro()
		tempo = inicio
		_sons_do_quadro()
	else:
		total_ataque = maxi(int(g["startup"]) + int(g["active"]), 1)
	pulse_ocioso = 0
	pulse = minf(100.0, pulse + float(q["pulse"]))
	if pulse >= 100.0:
		flatline = true
	eventos.append({"tipo": "quick", "golpe": {}})


# Qual dos 4 pulos do arquivo o comando atual pede ("" = nenhum).
func _escolher_pulo() -> String:
	var pulos: Dictionary = forge.get("pulos", {})
	var melhor: String = ""
	var melhor_peso: int = -1
	for nome in PULOS_PADRAO.keys():
		if not pulos.has(nome):
			continue
		var inp: Dictionary = (pulos[nome] as Dictionary).get("input", {})
		if inp.is_empty():
			inp = PULOS_PADRAO[nome]
		var n: int = _casa_input(inp)
		if n < 0:
			continue
		var peso: int = n * 2 + (1 if str(inp.get("botao", "")) != "" else 0)
		if peso > melhor_peso:
			melhor_peso = peso
			melhor = str(nome)
	return melhor


func _limpar_reacoes() -> void:
	_stun = false
	_imposing = false
	_wall = false
	_wall_pousou = false
	_wall_pouso_t = 0
	_ricochete = false
	_ricochete_volta = false
	_queda_tras = false
	arremessado = false


# Há quantos ticks a animação atual toca (reinicia quando troca de animação), cursor dos moves com
# "parar_se" e sons do início do frame.
func _atualizar_anim() -> void:
	if forge.is_empty():
		return
	if _manter != "" and _cur_fim:
		_manter = ""
	var nm: String = nome_move()
	if nm != _anim_nome:
		var ant: Dictionary = {} if _anim_nome == "" else move_resolvido(_anim_nome)
		var livre: bool = estado == Estado.PARADO or estado == Estado.ANDANDO or estado == Estado.DEFENDENDO
		if _manter == "" and livre and not _cur_fim and bool(ant.get("dinamico", false)) and bool(ant.get("fases", false)):
			# Saiu de um movimento com fases (ex.: soltou o analógico): toca o recovery antes de seguir.
			_manter = _anim_nome
			_cur_forcar = true
			nm = _anim_nome
		else:
			_manter = ""
			_anim_nome = nm
			_anim_t = 0
			_cur_i = 0
			_cur_t = 0
			_cur_est = {"pass": {}, "dir": {}}
			_cur_fim = false
			_cur_forcar = false
	else:
		_anim_t += 1
		_cur_passo()
	if _wall_pousou and _wall_pouso_t == 0:
		_wall_pouso_t = maxi(_anim_t, 1)
	_sons_forge()


# Um tick do cursor: ao acabar os ticks do frame, escolhe o próximo (trechos, vai_e_volta, parar_se).
func _cur_passo() -> void:
	var m: Dictionary = move_resolvido(_anim_nome)
	if m.is_empty() or not bool(m.get("dinamico", false)) or _cur_fim:
		return
	var frames: Array = m["frames"]
	_cur_i = clampi(_cur_i, 0, frames.size() - 1)
	_cur_t += 1
	if _cur_t < int(frames[_cur_i]["ticks"]):
		return
	var trechos: Array = m["trechos"]
	var k: int = Formato.trecho_de(trechos, _cur_i)
	var parar: bool = k >= 0 and _parar_ok(trechos[k]["parar"])
	var prox: int = Formato.proximo_frame(_cur_i, frames.size(), trechos, _cur_est, parar, _cur_forcar)
	_cur_t = 0
	if prox < 0:
		_cur_fim = true
	else:
		_cur_i = prox


# Condições "parar_se" do trecho (analógico relativo ao lado do personagem, botões, colisão, acerto).
func _parar_ok(lista: Array) -> bool:
	var dig: int = int(_hist[_hist.size() - 1]) if not _hist.is_empty() else 5
	for c in lista:
		var v: String = str(c["valor"])
		match str(c["k"]):
			"analogico_igual":
				if dig == v.to_int():
					return true
			"analogico_diferente":
				if dig != v.to_int():
					return true
			"botao_apertado":
				if bool(_bt_antes.get(v, false)):
					return true
			"botao_solto":
				if not bool(_bt_antes.get(v, false)):
					return true
			"colisao":
				if v == "parede" and (pos.x <= LIMITE_ESQ + 1.0 or pos.x >= LIMITE_DIR - 1.0):
					return true
				if v == "chao" and not no_chao:
					return true
				if v == "oponente" and oponente != null and absf(pos.x - oponente.pos.x) < (largura_corpo() + oponente.largura_corpo()) * 0.5:
					return true
			"acertou":
				if golpe_acertou:
					return true
	return false


# Há um movimento com fases em andamento que não aceita ser quebrado por este golpe (nao_quebra)?
func _espera_recovery(g: Dictionary) -> bool:
	if _anim_nome == "" or _cur_fim:
		return false
	var m: Dictionary = move_resolvido(_anim_nome)
	if not bool(m.get("fases", false)) or not bool(m.get("dinamico", false)):
		return false
	for nome in m.get("nao_quebra", []):
		if _eh_golpe(g, str(nome)):
			return true
	return false


func _sons_forge() -> void:
	var f: Dictionary = quadro_forge()
	if f.is_empty():
		return
	var idx: int = int(f["i"])
	if _anim_nome == _som_nome and idx == _som_idx:
		return
	_som_nome = _anim_nome
	_som_idx = idx
	_emitir_sons(f, "inicio")


func _emitir_sons(f: Dictionary, quando: String) -> void:
	for s in f.get("sons", []):
		if str(s["quando"]) == quando:
			eventos.append({"tipo": "som_forge", "golpe": {}, "arquivo": str(s["arquivo"]), "vol": float(s["vol"]), "canal": str(s["canal"])})


# Sons "acertar" e "bloqueado" do frame atual do golpe (a Luta chama quando o golpe conecta).
func emitir_sons_golpe(quando: String) -> void:
	if tem_forge():
		_emitir_sons(quadro_forge(), quando)


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
	_grav = GRAVIDADE
	_pulo_atual = ""
	_pulo_ticks = 0
	_hist_bt.clear()
	_bt_antes = {}
	_anim_nome = ""
	_anim_t = 0
	_som_nome = ""
	_som_idx = -1
	_manter = ""
	_pendente = {}
	_limpar_reacoes()

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
		_atualizar_anim()
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
	var borda := {}
	for k in apertados.keys():
		if bool(apertados[k]) and not bool(_bt_antes.get(k, false)):
			borda[k] = true
	_bt_antes = apertados.duplicate()
	_hist_bt.append(borda)
	if _hist_bt.size() > 40:
		_hist_bt.pop_front()
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
	_atualizar_anim()


func _estado_livre(dir: Vector2, apertados: Dictionary, atras: bool, cima: bool) -> void:
	var pulos_arquivo: bool = not (forge.get("pulos", {}) as Dictionary).is_empty()
	if _modo_arquivo:
		# Formato 2: o comando de cada golpe e de cada pulo vem do arquivo.
		if not _pendente.is_empty():
			# Golpe que esperava o recovery do movimento (nao_quebra): sai quando o recovery acaba.
			_pendente_t += 1
			_cur_forcar = true
			if _cur_fim or _pendente_t > 90 or not _espera_recovery(_pendente["g"]):
				var ped: Dictionary = _pendente
				_pendente = {}
				_executar_arquivo(ped)
				return
		var sel: Dictionary = _escolher_golpe_arquivo(apertados)
		if not sel.is_empty():
			if _pendente.is_empty() and _espera_recovery(sel["g"]):
				_pendente = sel
				_pendente_t = 0
				_cur_forcar = true
			else:
				_executar_arquivo(sel)
				return
		if pulos_arquivo and not no_chao:
			var pulo: String = _escolher_pulo()
			if pulo != "":
				_iniciar_decolagem(dir, pulo)
				return
	if apertados.get("ESQ", false) and not no_chao and esquiva_trava == 0:
		_iniciar_esquiva(dir)
		return
	if not _modo_arquivo:
		var rev: String = _quick_pedido(apertados)
		if rev != "" and _tentar_quick(rev):
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
	if cima and not pulos_arquivo:
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
		if str(d.get("comando", "")) != "" or not (d["input"] as Dictionary).is_empty() or not _condicoes_ok(d):
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
	# Formato 2: golpe com condição "depois de" interrompe o atual e começa no frame 0.
	if _modo_arquivo and _cadeia < 6:
		var enc: Dictionary = _escolher_golpe_arquivo(apertados, true)
		if not enc.is_empty():
			_cadeia += 1
			_executar_arquivo(enc, true)
			return
	# Quick logo depois de começar um golpe (soco fraco e depois o forte) vira o golpe forte na hora.
	if tempo <= QUICK_JANELA_COMBO and not _modo_arquivo:
		var rev: String = _quick_pedido(apertados)
		if rev != "" and _tentar_quick(rev):
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


func _quick_pedido(apertados: Dictionary) -> String:
	if bool(apertados.get("QP", false)):
		return "P"
	if bool(apertados.get("QK", false)):
		return "K"
	if bool(apertados.get("QB", false)):
		return "B"
	return ""


# Executa o golpe forte (HP, HK ou BO) direto na parte ativa. Devolve false se não deu.
func _tentar_quick(tipo: String) -> bool:
	if flatline:
		return false
	var botao: String = "HP" if tipo == "P" else ("HK" if tipo == "K" else "BO")
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
	eventos.append({"tipo": "quick", "golpe": {}})
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
		_hist_golpes.append({"nome": str(g.get("nome", "")), "move": str(g.get("forge_move", "")), "acertou": golpe_acertou, "t": relogio})
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
func _iniciar_decolagem(dir: Vector2, pulo: String = "") -> void:
	_pulo_atual = pulo
	pulo_sombra = pulo.begins_with("sombra") if pulo != "" else frames_desde_baixo <= JANELA_PULO_SOMBRA
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
	var dados_pulo: Dictionary = (forge.get("pulos", {}) as Dictionary).get(_pulo_atual, {})
	if _pulo_atual != "" and not dados_pulo.is_empty():
		# Pulo do arquivo: altura (px), ticks no ar e avanço (px) vêm da Forge. Parábola simétrica.
		var t_ar: float = float(int(dados_pulo["ticks"])) * DT
		var altura: float = float(dados_pulo["altura"]) * escala_sprite
		_pulo_ticks = int(dados_pulo["ticks"])
		_grav = 8.0 * altura / (t_ar * t_ar)
		vel.y = -4.0 * altura / t_ar
		var lado: float = 0.0 if absf(pulo_direcao_x) < 0.1 else signf(pulo_direcao_x)
		vel.x = lado * float(dados_pulo["avanco"]) * escala_sprite / t_ar * _mult_vel()
	else:
		_pulo_ticks = 0
		_grav = GRAVIDADE
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
		_limpar_reacoes()
		estado = Estado.LEVANTANDO
		tempo = 0
		duracao = ESQUIVA_FRAMES
		vel.x = 0.0
		return
	if tempo >= duracao and not arremessado:
		_limpar_reacoes()
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
	_stun = false
	_imposing = false


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


func _tem_prop(g: Dictionary, k: String) -> bool:
	for p in g.get("props", []):
		if str(p["k"]) == k:
			return true
	return false


func receber_acerto(g: Dictionary, dano: float) -> void:
	reacao_nivel = str(g.get("nivel", "mid"))
	var era_caido: bool = estado == Estado.CAIDO
	_limpar_reacoes()
	_pendente = {}
	_manter = ""
	vida = maxf(0.0, vida - dano)
	golpe_atual = {}
	bloqueado = false
	tempo = 0
	if vida <= 0.0:
		estado = Estado.KO
		vel.x = 0.0
		return
	var arquivo: bool = not (g.get("input", {}) as Dictionary).is_empty()
	# Propriedades do golpe (Formato 2). wall, ricochete e imposing ignoram o bloco hit.
	if _tem_prop(g, "imposing"):
		eventos.append({"tipo": "acerto", "golpe": g})
		estado = Estado.GOLPEADO
		duracao = IMPOSING_FRAMES
		_imposing = true
		vel = Vector2.ZERO
		return
	var parede: bool = _tem_prop(g, "wall") or _tem_prop(g, "ricochete")
	var blowoff: bool = g["blowoff"]
	var queda: bool = _tem_prop(g, "queda") or _tem_prop(g, "no_recovery")
	var knock: bool = era_caido or bool(g["antichao"]) or blowoff or parede or queda or (not arquivo and int(g["forca"]) >= 3)
	reacao = _classificar_reacao(g, knock)
	eventos.append({"tipo": "acerto", "golpe": g})
	var hit: Dictionary = g.get("hit", {})
	if knock:
		estado = Estado.CAIDO
		duracao = CAIDO_BLOWOFF if blowoff else CAIDO_FRAMES
		caido_recuperavel = not (blowoff or parede or _tem_prop(g, "no_recovery"))
		for p in g.get("props", []):
			if str(p["k"]) == "queda" and str(p["estagio"]) == "tras":
				_queda_tras = true
		vel.x = 0.0 if era_caido else _empurrao_base() * 120.0
		if parede:
			var dir: float = _direcao_para_longe()
			var alvo: float = LIMITE_DIR if dir > 0.0 else LIMITE_ESQ
			_wall = true
			duracao = 150
			_ricochete = _tem_prop(g, "ricochete")
			_wall_prox = 1.0 - clampf(absf(alvo - pos.x) / (TELA_LARGURA * 0.5), 0.0, 1.0)
			_lancar_arco(alvo, ARREMESSO_FRAMES)
		elif blowoff:
			_arremessar()
		elif not hit.is_empty():
			_aplicar_hit(hit)
	else:
		estado = Estado.GOLPEADO
		duracao = HITSTUN
		vel.x = _empurrao_base() * 60.0
		if _tem_prop(g, "stun"):
			_stun = true
			duracao = STUN_FRAMES
		elif not hit.is_empty():
			duracao = int(hit["tempo"])
			_aplicar_hit(hit)


# Bloco hit: dx (px para trás, negativo puxa), dy (px para cima). O deslize termina em dx porque a
# velocidade horizontal cai 15% por tick.
func _aplicar_hit(hit: Dictionary) -> void:
	vel.x = _empurrao_base() * float(hit["dx"]) * escala_sprite * 0.15 / DT
	var dy: float = float(hit["dy"]) * escala_sprite
	if dy > 0.0:
		no_chao = true
		_grav = GRAVIDADE
		vel.y = -sqrt(2.0 * GRAVIDADE * dy)


# Arremesso do Blow Off. A direção é para longe de quem bateu. Na metade da tela para onde ele está sendo
# jogado (perto da parede), ele vai até a parede; na outra metade, só é jogado ARREMESSO_DISTANCIA.
func _arremessar() -> void:
	var dir: float = _direcao_para_longe()
	var meio: float = TELA_LARGURA * 0.5
	var perto_da_parede: bool = (dir > 0.0 and pos.x > meio) or (dir < 0.0 and pos.x < meio)
	var alvo: float
	if perto_da_parede:
		alvo = LIMITE_DIR if dir > 0.0 else LIMITE_ESQ
	else:
		alvo = clampf(pos.x + dir * ARREMESSO_DISTANCIA, LIMITE_ESQ, LIMITE_DIR)
	_lancar_arco(alvo, ARREMESSO_FRAMES)


# Direção (+1 ou -1) para longe de quem bateu.
func _direcao_para_longe() -> float:
	if oponente != null and not is_equal_approx(pos.x, oponente.pos.x):
		return 1.0 if pos.x > oponente.pos.x else -1.0
	return _empurrao_base()


# Voa em arco até alvo_x em "frames" ticks. altura < 0 usa a gravidade normal (arco baixo do Blow Off).
func _lancar_arco(alvo_x: float, frames: int, altura: float = -1.0) -> void:
	var t_ar: float = float(frames) * DT
	_grav = GRAVIDADE if altura < 0.0 else 8.0 * altura / (t_ar * t_ar)
	arremessado = true
	no_chao = true
	vel.x = (alvo_x - pos.x) / t_ar
	vel.y = -_grav * DT * float(frames + 1) * 0.5


# Ricochete: bateu na parede e volta rebatido para o oponente. Quanto mais perto da parede estava, mais alto
# sobe, nunca acima do topo da tela.
func _ricochete_para_oponente() -> void:
	_ricochete = false
	_ricochete_volta = true
	_wall = false
	var alvo: float = oponente.pos.x if oponente != null else (LIMITE_ESQ + LIMITE_DIR) * 0.5
	var altura: float = minf(110.0 + 260.0 * _wall_prox, CHAO_Y - 40.0)
	_lancar_arco(clampf(alvo, LIMITE_ESQ, LIMITE_DIR), 44, altura)


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
		vel.y += _grav * DT
	else:
		ar_tempo = 0
	pos += vel * DT
	if pos.y >= CHAO_Y:
		pos.y = CHAO_Y
		if no_chao:
			no_chao = false
			vel.y = 0.0
			_grav = GRAVIDADE
			_pulo_atual = ""
			_pulo_ticks = 0
			if arremessado:
				arremessado = false
				vel.x = 0.0
				if _wall:
					_wall_pousou = true
				if _ricochete:
					_ricochete_para_oponente()
			# Pouso: deslize horizontal do pulo ou do ataque aéreo para no chão.
			if estado == Estado.PULANDO or estado == Estado.ATACANDO:
				vel.x = 0.0
			if estado == Estado.PULANDO:
				estado = Estado.PARADO
	pos.x = clampf(pos.x, LIMITE_ESQ, LIMITE_DIR)


func nome_estado() -> String:
	return NOMES_ESTADO[estado]