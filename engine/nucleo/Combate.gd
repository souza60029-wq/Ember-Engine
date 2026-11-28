extends RefCounted

# AJUSTES DE COMBATE. Mude aqui os números do combate; o Personagem lê tudo deste arquivo.
# Tempos em ticks (60 por segundo), distâncias em px (a tela é 960 x 540), velocidades em px/s.
# Todas as barras valem 100: vida, defesa (guarda), Pulse e especial.


# Pulos (altura, ticks no ar e avanço vêm do .ember; estes valem para personagens sem "pulos")
const GRAVIDADE: float = 2300.0 * 1.25
const VEL_NORMAL_ALTO: float = -1090.0
const VEL_NORMAL_BAIXO: float = -800.0
const VEL_SOMBRA_ALTO: float = -1360.0
const VEL_SOMBRA_BAIXO: float = -1000.0
const DECOLAGEM_NORMAL: int = 4
const DECOLAGEM_SOMBRA: int = 2
const JANELA_PULO_SOMBRA: int = 6
const DIRECAO_SALTO_MIN: float = 0.3

# Movimento e palco
const VEL_ANDAR: float = 400.0
const CHAO_Y: float = 480.0
const LIMITE_ESQ: float = 90.0
const LIMITE_DIR: float = 870.0
const TELA_LARGURA: float = 960.0

# Blow Off e arremessos
const ARREMESSO_FRAMES: int = 36
const ARREMESSO_DISTANCIA: float = 280.0

# Reações ao acerto
const HITSTUN: int = 18
const HITSTUN_BLOWBACK: int = 20
const BLOQUEIO: int = 10
const CAIDO_FRAMES: int = 36
const CAIDO_BLOWOFF: int = 90
const LEVANTAR_FRAMES: int = 18
const IMPOSING_FRAMES: int = 90
const STUN_FRAMES: int = 90

# Esquiva
const ESQUIVA_FRAMES: int = 22
const ESQUIVA_VEL: float = 520.0
const ESQUIVA_RECARGA: int = 20
const CUSTO_LEVANTAR: float = 5.0

# Defesa e parry
const JANELA_PARRY: int = 5
const PARRY_FRAMES: int = 14
const PARRY_AVISO: int = 40
const GUARDA_MAX: float = 100.0
const GUARDA_CUSTO := {1: 14.0, 2: 20.0, 3: 28.0}   # gasto da defesa por força do golpe (1, 2, 3)
const GUARDA_QUEBRADA_FRAMES: int = 75
const GUARDA_REGEN_ESPERA: int = 60
const GUARDA_REGEN_POR_FRAME: float = 0.4

# Dano e combo
const FORCA_FORTE: int = 2
const REDUCAO_DANO_FORTE: float = 0.30
const JANELA_COMBO: int = 50

# Quick, Pulse e Flatline
const PULSE_POR_USO: float = 30.0
const PULSE_ESPERA: int = 120
const PULSE_DECAI_FRAME: float = 99.0 / 300.0
const FLATLINE_VEL: float = 0.7
const FLATLINE_GUARDA: float = 1.15
const QUICK_JANELA_COMBO: int = 4

# Especial (barra de 100 = 5 estoques de 20)
const CUSTO_GUARD_CANCEL: float = 10.0

# Movimentos com input do arquivo
const VEL_ANDAR_COSTAS: float = 0.5      # fração da VEL_ANDAR ao andar para trás
const VEL_CORRER: float = 640.0          # correndo (comando [6,6] do arquivo)

# Stun por dano: quem sofre este % de vida sem causar nenhum dano ao adversário fica atordoado
const STUN_DANO_PCT: float = 25.0

# Quick recovery: ESQ ao cair, com o corpo até esta altura (px acima do chão, altura da canela), faz roll_back
const ALTURA_CANELA: float = 60.0
const ROLL_BACK_FRAMES: int = 22

# "Próximo sprite se...": tempo máximo (ticks) que um frame espera o evento antes de seguir sozinho
const PROXIMO_TIMEOUT: int = 180

