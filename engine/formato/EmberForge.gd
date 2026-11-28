extends RefCounted

# Lê o arquivo .ember gerado pelo Ember Forge (JSON com sprites em base64, boxes por frame, ticks,
# fases, magias e condições; ver EMBER_FORMAT.md) e monta um personagem no formato da engine.
# Os sprites viram PNGs em <pasta>/sprites/. As boxes ficam em "forge.moves" (px do sprite, x+ = frente).
# Formato 2: inputs, pulos, quick, props, hit, dano, repetições e sons vêm no arquivo. O que a Forge
# NÃO manda (força, custo, física) a engine decide aqui. Arquivos v1 continuam valendo.

const Formato = preload("res://engine/formato/Formato.gd")

const MAX_TICKS := 220
# TAMANHO DO PERSONAGEM NA TELA: altura em px (de 540) que o primeiro quadro de "parado" ocupa.
# Era 320; agora 240 (25% menor). Mude este valor para aumentar ou diminuir todos os personagens.
const ALTURA_ALVO := 240.0
# Se true, a escala é arredondada para baixo em número inteiro (pixels nítidos, mas o tamanho pula de
# 2x para 3x). Com false, o tamanho segue ALTURA_ALVO exatamente.
const ESCALA_INTEIRA := false
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

	# 1b) sons (tabela deduplicada): gravados em pasta/sons/. Só wav, mp3 e ogg tocam na engine.
	var sons_arq := {}   # id -> "sons/xxx.ext"
	var sons_ignorados: int = 0
	if typeof(raiz.get("sons", null)) == TYPE_DICTIONARY:
		DirAccess.make_dir_recursive_absolute(pasta + "sons/")
		for sid in (raiz["sons"] as Dictionary).keys():
			var si: Variant = raiz["sons"][sid]
			if typeof(si) != TYPE_DICTIONARY:
				continue
			var ext: String = str((si as Dictionary).get("formato", "")).to_lower()
			if not ["wav", "mp3", "ogg"].has(ext):
				sons_ignorados += 1
				continue
			var dados: String = str(si.get("dados", ""))
			var vir: int = dados.find(",")
			if vir >= 0:
				dados = dados.substr(vir + 1)
			var sb: PackedByteArray = Marshalls.base64_to_raw(dados)
			if sb.is_empty():
				continue
			var arq_som: String = "sons/" + _arq(str(sid)) + "." + ext
			var fs := FileAccess.open(pasta + arq_som, FileAccess.WRITE)
			if fs == null:
				continue
			fs.store_buffer(sb)
			fs.close()
			sons_arq[str(sid)] = arq_som

	# 2) moves
	var moves := {}
	for nome in (raiz["moves"] as Dictionary).keys():
		var m: Variant = raiz["moves"][nome]
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mv: Dictionary = _move(str(nome), m, arquivos, tamanhos, espelha, vazios, sons_arq)
		if not (mv["frames"] as Array).is_empty() or str(mv["tipo"]) == "Golpes":
			moves[str(nome)] = mv
	if not moves.has("parado") or (moves["parado"]["frames"] as Array).is_empty():
		return _falha("O personagem precisa ter o estado 'parado' com sprites.")

	# 3) tamanho na tela
	var pf: Dictionary = moves["parado"]["frames"][0]
	var altura: float = maxf(float(pf["h"]), 8.0)
	var esc: float = ALTURA_ALVO / altura
	esc = float(floori(esc)) if (ESCALA_INTEIRA and esc >= 2.0) else esc
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
			if (mv["input"] as Dictionary).is_empty():
				# Arquivo v1 (sem input): a engine escolhe um comando.
				g["comando"] = COMANDOS_CUSTOM[n_custom % COMANDOS_CUSTOM.size()]
				g["botao"] = "LP" if str(g["comando"]).ends_with("P") else "LK"
				n_custom += 1
		g["forge_move"] = str(nome)
		if str(mv["nome"]) != "":
			g["nome"] = str(mv["nome"])
		g["categoria"] = str(mv["categoria"])
		g["versao"] = str(mv["versao"])
		g["versao_fraca"] = str(mv["versao_fraca"])
		g["versao_forte"] = str(mv["versao_forte"])
		# Formato 2: comando, quick, propriedades, hit e dano vêm do arquivo.
		g["input"] = mv["input"]
		if not (mv["input"] as Dictionary).is_empty() and str((mv["input"] as Dictionary)["botao"]) != "" and str((mv["input"] as Dictionary)["botao"]) != "ESQ":
			g["botao"] = str((mv["input"] as Dictionary)["botao"])
		g["quick"] = mv["quick"]
		g["props"] = mv["props"]
		g["hit"] = mv["hit"]
		g["dano_pct"] = float(mv["dano"])
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
			"forge": {"moves": forge_moves, "pulos": _pulos(raiz.get("pulos", null)), "sons_ignorados": sons_ignorados,
				"config": _config(raiz.get("config", null)), "movelist": _movelist(raiz.get("movelist", null)),
				"ordem": _lista_texto(raiz.get("ordem", null))},
		},
	}


# Os 4 pulos do arquivo: altura (px), ticks no ar, avanço (px) e comando. Vazio = valores da engine.
static func _pulos(v: Variant) -> Dictionary:
	var r := {}
	if typeof(v) != TYPE_DICTIONARY:
		return r
	for k in ["normal", "alto", "sombra_alto", "sombra_baixo"]:
		var p: Variant = (v as Dictionary).get(k, null)
		if typeof(p) != TYPE_DICTIONARY:
			continue
		r[k] = {"altura": clampf(float(p.get("altura", 140.0)), 10.0, 800.0),
			"ticks": clampi(int(p.get("ticks_no_ar", 50)), 10, 300),
			"avanco": clampf(float(p.get("avanco", 0.0)), 0.0, 1200.0),
			"saida": clampi(int(p.get("saida_ticks", 0)), 0, 60),   # ticks no chão (agachada) antes de sair
			"input": Formato.normalizar_input(p.get("input", {}))}
	return r


static func _lista_texto(v: Variant) -> Array:
	var r: Array = []
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			r.append(str(x))
	return r


# Config já resolvida pela Forge (padrão global ou do personagem). Vazio = a engine usa os padrões dela.
static func _config(v: Variant) -> Dictionary:
	var r := {}
	if typeof(v) != TYPE_DICTIONARY:
		return r
	var c: Dictionary = v
	if typeof(c.get("corrida", null)) == TYPE_DICTIONARY:
		r["corrida"] = {"janela": clampi(int(c["corrida"].get("janela_ticks", 15)), 1, 60), "vel": clampf(float(c["corrida"].get("velocidade_px_s", 260.0)), 0.0, 2000.0)}
	if typeof(c.get("andar", null)) == TYPE_DICTIONARY:
		r["andar"] = {"frente": clampf(float(c["andar"].get("frente_px_s", 120.0)), 0.0, 2000.0), "tras": clampf(float(c["andar"].get("tras_px_s", 90.0)), 0.0, 2000.0)}
	if typeof(c.get("backdash", null)) == TYPE_DICTIONARY:
		r["backdash"] = {"janela": clampi(int(c["backdash"].get("janela_ticks", 15)), 1, 60), "dist": clampf(float(c["backdash"].get("distancia_px", 90.0)), 0.0, 1500.0), "ticks": clampi(int(c["backdash"].get("ticks", 20)), 1, 120)}
	if typeof(c.get("roll", null)) == TYPE_DICTIONARY:
		r["roll"] = {"dist": clampf(float(c["roll"].get("distancia_px", 110.0)), 0.0, 1500.0), "ticks": clampi(int(c["roll"].get("ticks", 26)), 1, 120)}
	if c.has("buffer_ticks"):
		r["buffer"] = clampi(int(c["buffer_ticks"]), 0, 30)
	return r


# Lista da movelist já pronta pela Forge (a tela de movelist usa isto). Só dados simples.
static func _movelist(v: Variant) -> Array:
	var r: Array = []
	if typeof(v) != TYPE_ARRAY:
		return r
	for e in v:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		r.append({"id": str(e.get("id", "")), "nome": str(e.get("nome", "")), "categoria": str(e.get("categoria", "padrao")),
			"categoria_nome": str(e.get("categoria_nome", "")), "dano": float(e.get("dano", 0.0)),
			"comando": Formato.normalizar_input(e.get("comando", {})), "comando_texto": str(e.get("comando_texto", "")),
			"versao": str(e.get("versao", "unica")), "versao_fraca": str(e.get("versao_fraca", "")), "versao_forte": str(e.get("versao_forte", ""))})
	return r


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


# "Próximo sprite se...": {se, sub, espera (ticks)}. Vazio = só pelo tempo.
static func _proximo(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY or not ["colisao", "acertou", "botao"].has(str(v.get("se", ""))):
		return {}
	return {"se": str(v["se"]), "sub": str(v.get("sub", "")), "espera": clampi(int(round(float(v.get("espera_ms", 0)) * 60.0 / 1000.0)), 0, 600)}


# Sons do frame: [{arquivo, vol (0-1), canal (sfx|voz), quando (inicio|acertar|bloqueado)}].
static func _sons_frame(v: Variant, sons_arq: Dictionary) -> Array:
	var r: Array = []
	if typeof(v) != TYPE_ARRAY:
		return r
	for s in v:
		if typeof(s) == TYPE_DICTIONARY and sons_arq.has(str(s.get("id", ""))):
			var q: String = str(s.get("quando", "inicio"))
			r.append({"arquivo": sons_arq[str(s["id"])], "vol": clampf(float(s.get("vol", 100)) / 100.0, 0.0, 1.0),
				"canal": "voz" if str(s.get("canal", "sfx")) == "voz" else "sfx",
				"quando": q if ["inicio", "acertar", "bloqueado"].has(q) else "inicio"})
	return r


# Repetições do move já com os índices desta lista de frames:
# [{de, ate, vezes, modo (normal|vai_e_volta), saida (fim_do_ciclo|imediata), parar: [{k, valor}]}].
static func _trechos(v: Variant, mapa: Dictionary) -> Array:
	var r: Array = []
	if typeof(v) != TYPE_ARRAY:
		return r
	for t in v:
		if typeof(t) == TYPE_DICTIONARY and mapa.has(int(t.get("de", -1))) and mapa.has(int(t.get("ate", -1))):
			var parar: Array = []
			if typeof(t.get("parar_se", [])) == TYPE_ARRAY:
				for c in t["parar_se"]:
					if typeof(c) == TYPE_DICTIONARY and ["analogico_igual", "analogico_diferente", "botao_apertado", "botao_solto", "colisao", "acertou"].has(str(c.get("k", ""))):
						parar.append({"k": str(c["k"]), "valor": str(c.get("valor", ""))})
			r.append({"de": int(mapa[int(t["de"])]), "ate": int(mapa[int(t["ate"])]), "vezes": maxi(int(t.get("vezes", 1)), 0),
				"modo": "vai_e_volta" if str(t.get("modo", "normal")) == "vai_e_volta" else "normal",
				"saida": "imediata" if str(t.get("saida", "fim_do_ciclo")) == "imediata" else "fim_do_ciclo", "parar": parar})
	return r


# Um índice de frame por tick, já com as repetições (sem olhar o analógico: "parar_se" é resolvido na hora,
# pela engine, nos moves "dinamico"). "loop" é a parte que repete para sempre (vezes 0); travar_em segura o
# último frame. Ver "Repetições e fim da animação" no EMBER_FORMAT.md e o adendo de loop e fases.
static func _linha_do_tempo(frames: Array, trechos: Array, travar: int) -> Dictionary:
	var cron: Array = []
	var estado := {"pass": {}, "dir": {}}
	var i: int = 0
	var visitas: int = 0
	while i >= 0 and i < frames.size() and visitas < 800 and cron.size() < 1200:
		visitas += 1
		var k: int = Formato.trecho_de(trechos, i)
		if k >= 0 and int(trechos[k]["vezes"]) == 0 and i == int(trechos[k]["de"]):
			# entrou num trecho infinito: um ciclo dele repete para sempre
			var t: Dictionary = trechos[k]
			var ordem: Array = range(int(t["de"]), int(t["ate"]) + 1)
			if str(t["modo"]) == "vai_e_volta":
				for j in range(int(t["ate"]) - 1, int(t["de"]), -1):
					ordem.append(j)
			var lp: Array = []
			for j in ordem:
				for q in range(int(frames[j]["ticks"])):
					lp.append(j)
			return {"cron": cron, "loop": lp}
		for q in range(int(frames[i]["ticks"])):
			cron.append(i)
		if i == travar:
			break
		i = Formato.proximo_frame(i, frames.size(), trechos, estado, false)
	return {"cron": cron, "loop": []}


static func _move(nome: String, m: Dictionary, arquivos: Dictionary, tamanhos: Dictionary, espelha: bool, vazios: Dictionary, sons_arq: Dictionary = {}) -> Dictionary:
	var frames: Array = []
	var cron: Array = []         # um índice de frame por tick
	var sprites_ticks: Array = []
	var sids: Array = []
	var mapa := {}               # índice do frame no arquivo -> índice nesta lista
	var lista: Variant = m.get("frames", [])
	if typeof(lista) == TYPE_ARRAY:
		for pos_fr in range((lista as Array).size()):
			var fr: Variant = lista[pos_fr]
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
						tags.append({"k": str(t.get("k", "")), "modo": "fica" if str(t.get("modo", "atravessa")) == "fica" else "atravessa",
							"vx": float(t.get("vx", 0)), "vy": float(t.get("vy", 0)), "alcance": float(t.get("alcance", 0)),
							"dur_ticks": clampi(int(t.get("dur_ticks", 90)), 1, 600)})
			var idx: int = frames.size()
			mapa[int(fr.get("i", pos_fr))] = idx
			sids.append(sid)
			frames.append({"i": idx, "dy": 0, "sprite": arquivos[sid], "w": tam.x, "h": tam.y, "ticks": ticks, "fase": str(fr.get("fase", "")),
				"boxes": boxes, "magia": magia, "tags": tags, "proximo": _proximo(fr.get("proximo", null)),
				"sons": _sons_frame(fr.get("sons", null), sons_arq)})
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
				conds.append({"k": str(c["k"]), "golpe": str(c.get("golpe", "")), "de": maxi(int(c.get("de", 0)), 0),
					"ate": int(c.get("ate", -1)), "apos_ticks": maxi(int(c.get("apos_ticks", 0)), 0)})
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
	# Repetições (trechos), travar_em e loop infinito. Sem esses campos: padrão do formato (EM_CICLO).
	var tem_rep: bool = m.has("trechos") or m.has("travar_em") or m.has("repeticao")
	var trechos: Array = _trechos(m.get("trechos", []), mapa)
	var dinamico: bool = false
	for tr in trechos:
		if not (tr["parar"] as Array).is_empty():
			dinamico = true
	for fr2 in frames:
		if not (fr2.get("proximo", {}) as Dictionary).is_empty():
			dinamico = true
	var nao_quebra: Array = []
	if typeof(m.get("nao_quebra", [])) == TYPE_ARRAY:
		for nq in m["nao_quebra"]:
			nao_quebra.append(str(nq))
	var linha: Dictionary = {"cron": cron, "loop": []}
	if tem_rep:
		linha = _linha_do_tempo(frames, trechos, int(mapa.get(int(m.get("travar_em", -1)), -1)))
	var props: Array = Formato._props(m.get("props", []))
	var dano: float = clampf(float(m.get("dano", -1.0)), -1.0, 100.0)
	return {
		"solta": solta,
		"tipo": tipo_m,
		"loop": EM_CICLO.has(nome) and not tem_rep,
		"ticks_total": cron.size(),
		"frames": frames,
		"cron": linha["cron"],
		"cron_loop": linha["loop"],
		"usa_trechos": tem_rep,
		"trechos": trechos,
		"dinamico": dinamico,           # tem "parar_se": a engine anda frame a frame (cursor)
		"fases": bool(m.get("fases", false)),
		"nome": str(m.get("nome", "")),
		"categoria": str(m.get("categoria", "padrao")),
		"versao": str(m.get("versao", "unica")),
		"versao_fraca": str(m.get("versao_fraca", "")),
		"versao_forte": str(m.get("versao_forte", "")),
		"nao_quebra": nao_quebra,
		"input": Formato.normalizar_input(m.get("input", {})),
		"quick": Formato._quick(m.get("quick", {})),
		"props": props,
		"hit": Formato._hit(m.get("hit", {})),
		"dano": dano,
		"sprites_ticks": sprites_ticks,
		"nivel": nivel,
		"condicoes": conds,
		"derivado": der,
		"magia": bool(m.get("magia", false)),
		"ancora": anc,
	}
