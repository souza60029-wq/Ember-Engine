extends RefCounted

# Lê o arquivo .ember gerado pelo Ember Forge (JSON com sprites em base64, boxes por frame, ticks,
# fases, magias e condições; ver EMBER_FORMAT.md) e monta um personagem no formato da engine.
# Os sprites viram PNGs em <pasta>/sprites/. As boxes ficam em "forge.moves" (px do sprite, x+ = frente).
# O que a Forge NÃO manda (inputs, dano, custo, movimento) a engine decide aqui.

const Formato = preload("res://engine/formato/Formato.gd")

const MAX_TICKS := 220
const ALTURA_ALVO := 320.0   # altura do personagem na tela (cerca de 60% de 540, como o KOF)
const MAX_SPRITES := 3000

# Slot antigo da engine -> move da Forge.
const SLOTS := {
	"parado": "parado", "andando": "andando_frente", "pulando": "pulando", "defendendo": "defesa_neutra",
	"bloqueio": "defesa_neutra", "golpeado_alto": "hit_overhead", "golpeado_medio": "hit_mid",
	"golpeado_baixo": "hit_low", "caido": "caindo_frente", "rasteira": "caindo_rolando",
	"levantando": "levantando_frente", "esquiva": "roll", "ko": "caindo_frente", "parry": "parry",
	"guarda_quebrada": "guarda_quebrada",
}
const PADRAO := {"low_punch": "LP", "low_kick": "LK", "high_punch": "HP", "high_kick": "HK", "blow_off": "BO"}
const EM_CICLO := ["parado", "afk", "andando_frente", "andando_costas", "agachado", "defesa_neutra", "defesa_alta",
	"defesa_agachado", "defesa_aerea", "correndo", "stun"]
# Comandos dos golpes "custom" (a Forge não define): na ordem em que aparecem no arquivo.
# Estados em que os pés ficam no chão: aqui a engine nivela os pés entre os quadros da mesma animação.
const NIVELA_PES := ["parado", "afk", "andando_frente", "andando_costas", "agachado", "correndo", "defesa_neutra",
	"defesa_alta", "defesa_agachado", "parry", "guarda_quebrada", "stun", "levantando_frente", "levantando_costas", "roll"]
const COMANDOS_CUSTOM := ["236P", "236K", "623P", "623K", "214P", "214K", "2363214P", "2363214K"]


static func eh_forge(texto: String) -> bool:
	var t: String = texto.strip_edges()
	return t.begins_with("{") and t.contains("\"ember_format\"")


static func _falha(msg: String) -> Dictionary:
	return {"ok": false, "erro": msg, "personagem": {}}


static func _arq(id: String) -> String:
	var r: String = ""
	for c in id.to_lower():
		r += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "_"
	return r.left(60)


# Converte o texto do .ember e grava os sprites em pasta/sprites/. Devolve {ok, erro, personagem}.
static func importar_texto(texto: String, pasta: String) -> Dictionary:
	var bruto: Variant = JSON.parse_string(texto)
	if typeof(bruto) != TYPE_DICTIONARY:
		return _falha("O arquivo .ember não é um JSON válido.")
	var raiz: Dictionary = bruto
	if int(raiz.get("ember_format", 0)) < 1:
		return _falha("Isso não é um arquivo do Ember Forge.")
	if typeof(raiz.get("sprites", null)) != TYPE_DICTIONARY or typeof(raiz.get("moves", null)) != TYPE_DICTIONARY:
		return _falha("O arquivo não tem 'sprites' e 'moves'.")
	var olhando: String = "esquerda" if str(raiz.get("olhando", "direita")) == "esquerda" else "direita"
	var espelha: bool = olhando == "esquerda"   # a arte olha para a esquerda: a "frente" é o x negativo

	# 1) sprites: cada PNG é gravado uma vez
	var tabela: Dictionary = raiz["sprites"]
	if tabela.size() > MAX_SPRITES:
		return _falha("Sprites demais no arquivo.")
	DirAccess.make_dir_recursive_absolute(pasta + "sprites/")
	var arquivos := {}   # id -> "sprites/xxx.png"
	var tamanhos := {}   # id -> Vector2i
	var vazios := {}     # id -> linhas transparentes na base do sprite
	for id in tabela.keys():
		var info: Variant = tabela[id]
		if typeof(info) != TYPE_DICTIONARY:
			continue
		var png: String = str((info as Dictionary).get("png", ""))
		var virgula: int = png.find(",")
		if virgula >= 0:
			png = png.substr(virgula + 1)
		var bytes: PackedByteArray = Marshalls.base64_to_raw(png)
		var img := Image.new()
		if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
			return _falha("Um sprite do arquivo está corrompido.")
		var nome_arq: String = "sprites/" + _arq(str(id)) + ".png"
		var f := FileAccess.open(pasta + nome_arq, FileAccess.WRITE)
		if f == null:
			return _falha("Não consegui gravar os sprites neste aparelho.")
		f.store_buffer(bytes)
		f.close()
		vazios[str(id)] = _vazio_embaixo(img)
		arquivos[str(id)] = nome_arq
		tamanhos[str(id)] = Vector2i(img.get_width(), img.get_height())

	# 2) moves
	var moves := {}
	for nome in (raiz["moves"] as Dictionary).keys():
		var m: Variant = raiz["moves"][nome]
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mv: Dictionary = _move(str(nome), m, arquivos, tamanhos, espelha, vazios)
		if not (mv["frames"] as Array).is_empty() or str(mv["tipo"]) == "Golpes":
			moves[str(nome)] = mv
	if not moves.has("parado") or (moves["parado"]["frames"] as Array).is_empty():
		return _falha("O personagem precisa ter o estado 'parado' com sprites.")

	# 3) tamanho na tela
	var pf: Dictionary = moves["parado"]["frames"][0]
	var altura: float = maxf(float(pf["h"]), 8.0)
	var esc: float = ALTURA_ALVO / altura
	esc = float(floori(esc)) if esc >= 2.0 else esc
	esc = clampf(esc, 1.0, 8.0)

	# 4) golpes da engine
	var golpes: Array = []
	var n_custom: int = 0
	for nome in moves.keys():
		var mv: Dictionary = moves[nome]
		var tipo: String = str(mv["tipo"])
		if tipo != "Padrao" and tipo != "Golpes":
			continue
		var g: Dictionary
		if PADRAO.has(nome):
			g = Formato.golpe_base(str(PADRAO[nome]))
		else:
			g = Formato.padrao_golpe()
			g["nome"] = str(nome).replace("_", " ").capitalize()
			g["dano"] = 80
			g["forca"] = 2
			g["comando"] = COMANDOS_CUSTOM[n_custom % COMANDOS_CUSTOM.size()]
			g["botao"] = "LP" if str(g["comando"]).ends_with("P") else "LK"
			n_custom += 1
		g["forge_move"] = str(nome)
		g["nivel"] = str(mv["nivel"])
		g["condicoes"] = mv["condicoes"]
		g["so_ar"] = false
		for c in mv["condicoes"]:
			if str((c as Dictionary)["k"]) == "no_ar":
				g["so_ar"] = true
		var d: Dictionary = mv["derivado"]
		var total: int = int(mv["ticks_total"])
		var ini: int = int(d["startup"])
		var ativo: int = maxi(int(d["active"]), 1)
		var rec: int = int(d["recovery"])
		if ini + ativo + rec < total:
			rec += total - (ini + ativo + rec)
		g["startup"] = ini
		g["active"] = ativo
		g["recovery"] = rec
		g["frames"] = mv["sprites_ticks"]
		var hb: Array = _primeira_hitbox(mv)
		if not hb.is_empty():
			g["hitbox"] = {"x": hb[0], "y": hb[1], "w": hb[2], "h": hb[3]}
		golpes.append(g)

	# 5) animações antigas (slots), usadas por telas que ainda não conhecem o formato novo
	var slots := {}
	for slot in SLOTS.keys():
		var alvo: String = str(SLOTS[slot])
		if moves.has(alvo):
			var lista: Array = []
			for fr in moves[alvo]["frames"]:
				lista.append(str(fr["sprite"]))
			slots[slot] = lista

	var nome_p: String = str(raiz.get("nome", "Sem nome")).strip_edges().left(40)
	if nome_p == "":
		nome_p = "Sem nome"
	var forge_moves := {}
	for k in moves.keys():
		var mv2: Dictionary = (moves[k] as Dictionary).duplicate()
		mv2.erase("sprites_ticks")
		forge_moves[k] = mv2
	return {
		"ok": true,
		"erro": "",
		"personagem": {
			"formato": Formato.VERSAO,
			"id": Formato.sanitizar_id(nome_p),
			"nome": nome_p,
			"altura_px": Formato.ALTURA_PADRAO,
			"olhando": olhando,
			"escala_forge": esc,
			"arte_card": str(pf["sprite"]),
			"arte_selecao": str(pf["sprite"]),
			"sprites": slots,
			"magias": [],
			"golpes": golpes,
			"forge": {"moves": forge_moves},
		},
	}


# Quantas linhas de baixo para cima são totalmente transparentes (distância dos pés até a borda do PNG).
static func _vazio_embaixo(img: Image) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.05:
				return img.get_height() - 1 - y
	return 0


# Sprites da mesma animação com os pés em alturas diferentes fariam o personagem "pular" entre
# os quadros. Usa-se como referência o espaço vazio mais comum da animação e cada quadro é
# deslocado para casar com ele. As boxes e a magia acompanham o sprite.
static func _nivelar_pes(frames: Array, sids: Array, vazios: Dictionary) -> void:
	if frames.size() < 2:
		return
	var cont := {}
	for sid in sids:
		var v: int = int(vazios.get(sid, 0))
		cont[v] = int(cont.get(v, 0)) + 1
	var ref: int = 0
	var melhor: int = -1
	for v in cont.keys():
		if int(cont[v]) > melhor or (int(cont[v]) == melhor and int(v) < ref):
			melhor = int(cont[v])
			ref = int(v)
	for i in range(frames.size()):
		var dy: int = int(vazios.get(sids[i], 0)) - ref
		if dy == 0:
			continue
		var fr: Dictionary = frames[i]
		fr["dy"] = dy
		for tipo in (fr["boxes"] as Dictionary).keys():
			for b in fr["boxes"][tipo]:
				b[1] = int(b[1]) + dy
		if typeof(fr["magia"]) == TYPE_DICTIONARY:
			fr["magia"]["y"] = int(fr["magia"]["y"]) + dy


static func _primeira_hitbox(mv: Dictionary) -> Array:
	for fr in mv["frames"]:
		if str(fr["fase"]) == "active":
			var l: Array = (fr["boxes"] as Dictionary).get("hitbox", [])
			if not l.is_empty():
				return l[0]
	return []


# Converte x/w de uma box para "frente positiva" (se a arte olha para a esquerda, espelha).
static func _caixa(b: Variant, espelha: bool) -> Array:
	if typeof(b) != TYPE_DICTIONARY:
		return []
	var x: int = int((b as Dictionary).get("x", 0))
	var y: int = int(b.get("y", 0))
	var w: int = maxi(1, int(b.get("w", 1)))
	var h: int = maxi(1, int(b.get("h", 1)))
	if espelha:
		x = -(x + w)
	return [x, y, w, h]


static func _move(nome: String, m: Dictionary, arquivos: Dictionary, tamanhos: Dictionary, espelha: bool, vazios: Dictionary) -> Dictionary:
	var frames: Array = []
	var cron: Array = []         # um índice de frame por tick
	var sprites_ticks: Array = []
	var sids: Array = []
	var lista: Variant = m.get("frames", [])
	if typeof(lista) == TYPE_ARRAY:
		for fr in lista:
			if typeof(fr) != TYPE_DICTIONARY:
				continue
			var cam: Dictionary = fr.get("camadas", {}) if typeof(fr.get("camadas", {})) == TYPE_DICTIONARY else {}
			var pers: Dictionary = cam.get("personagem", {}) if typeof(cam.get("personagem", {})) == TYPE_DICTIONARY else {}
			var sid: String = str(pers.get("sprite", ""))
			if not arquivos.has(sid):
				continue
			var tam: Vector2i = tamanhos[sid]
			var ticks: int = clampi(int(fr.get("ticks", 1)), 1, 120)
			var boxes := {}
			var bx: Dictionary = cam.get("boxes", {}) if typeof(cam.get("boxes", {})) == TYPE_DICTIONARY else {}
			for tipo in bx.keys():
				var out: Array = []
				if typeof(bx[tipo]) == TYPE_ARRAY:
					for b in bx[tipo]:
						var cx: Array = _caixa(b, espelha)
						if not cx.is_empty():
							out.append(cx)
				boxes[str(tipo)] = out
			var magia: Variant = null
			var mg: Variant = cam.get("magia", null)
			if typeof(mg) == TYPE_DICTIONARY and arquivos.has(str((mg as Dictionary).get("sprite", ""))):
				var mx: int = int(mg.get("x", 0))
				magia = {"sprite": arquivos[str(mg["sprite"])], "x": -mx if espelha else mx, "y": int(mg.get("y", 0)),
					"ocultar": bool(mg.get("ocultar_personagem", false))}
			var tags: Array = []
			var lista_tags: Variant = fr.get("tags", [])
			if typeof(lista_tags) == TYPE_ARRAY:
				for t in lista_tags:
					if typeof(t) == TYPE_DICTIONARY:
						tags.append({"k": str(t.get("k", "")), "modo": str(t.get("modo", "some")), "vx": float(t.get("vx", 0)),
							"vy": float(t.get("vy", 0)), "alcance": float(t.get("alcance", 0))})
			var idx: int = frames.size()
			sids.append(sid)
			frames.append({"i": idx, "dy": 0, "sprite": arquivos[sid], "w": tam.x, "h": tam.y, "ticks": ticks, "fase": str(fr.get("fase", "")),
				"boxes": boxes, "magia": magia, "tags": tags})
			for k in range(ticks):
				if cron.size() < MAX_TICKS:
					cron.append(idx)
					sprites_ticks.append(arquivos[sid])
	var tipo_m: String = str(m.get("tipo", "Basicos"))
	var no_ar: bool = false
	if typeof(m.get("condicoes", [])) == TYPE_ARRAY:
		for c0 in m.get("condicoes", []):
			if typeof(c0) == TYPE_DICTIONARY and str(c0.get("k", "")) == "no_ar":
				no_ar = true
	if NIVELA_PES.has(nome) or ((tipo_m == "Padrao" or tipo_m == "Golpes") and not no_ar):
		_nivelar_pes(frames, sids, vazios)
	var nivel: String = str(m.get("nivel", "mid"))
	if not ["mid", "low", "overhead"].has(nivel):
		nivel = "mid"
	var conds: Array = []
	var lista_conds: Variant = m.get("condicoes", [])
	if typeof(lista_conds) == TYPE_ARRAY:
		for c in lista_conds:
			if typeof(c) == TYPE_DICTIONARY and ["no_ar", "no_chao", "agachado", "depois_de", "depois_de_acertar"].has(str(c.get("k", ""))):
				conds.append({"k": str(c["k"]), "golpe": str(c.get("golpe", ""))})
	var der: Dictionary = {"startup": 0, "active": 0, "recovery": 0}
	if typeof(m.get("derivado_60fps", null)) == TYPE_DICTIONARY:
		for k in der.keys():
			der[k] = clampi(int((m["derivado_60fps"] as Dictionary).get(k, 0)), 0, 200)
	var anc: Variant = null
	if typeof(m.get("ancora", null)) == TYPE_DICTIONARY:
		var ax: int = int(m["ancora"].get("x", 0))
		anc = {"x": -ax if espelha else ax, "y": int(m["ancora"].get("y", 0))}
	var solta: int = -1
	for fr2 in frames:
		for t2 in fr2["tags"]:
			if solta < 0 and str(t2["k"]) == "solta":
				solta = int(fr2["i"])
	return {
		"solta": solta,
		"tipo": tipo_m,
		"loop": EM_CICLO.has(nome),
		"ticks_total": cron.size(),
		"frames": frames,
		"cron": cron,
		"sprites_ticks": sprites_ticks,
		"nivel": nivel,
		"condicoes": conds,
		"derivado": der,
		"magia": bool(m.get("magia", false)),
		"ancora": anc,
	}
