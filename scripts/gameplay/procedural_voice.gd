## Voz: sílabas do banco gerado, montadas em fala. Sem gravação e sem texto lido.
##
## É a mesma escolha estética da locomoção da fase 6. A fala não é atuada, é **sugerida** —
## e a 900 triângulos por rosto, com olho e boca sendo planos afundados na face, uma voz
## atuada prometeria uma fidelidade que a cara não entrega. O que se quer é o ritmo de
## alguém falando, não as palavras.
##
## **As sílabas vêm de `assets/generated/audio/voz/`**, sintetizadas por `tools/gen_audio.py`
## com formantes distintos por raça — F1 e F2 são as duas ressonâncias que o ouvido usa
## para reconhecer uma vogal, e mover as duas move a identidade de quem fala. Este arquivo
## não sintetiza mais nada: ele escolhe sílabas e as costura. Sintetizar em GDScript, como
## na fase 11, custava um laço de milhares de amostras por fala e não tinha como fazer
## formante — que é exatamente o que faltava para as raças soarem diferentes.
##
## **O pitch de cada habitante é derivado do nome dele.** Não é sorteado em runtime e não é
## guardado em lugar nenhum: `_hash` do nome dá o mesmo número em toda sessão, então o
## mesmo NPC tem a mesma voz sempre, e a população inteira tem vozes distintas sem uma
## tabela de vinte entradas que alguém teria de manter.
##
## O timbre vem da **postura do corpo**, que é o que o elenco já declara e o que
## `GaitProfile` também usa. Um corpo novo herda voz sem tabela nova — do mesmo jeito que
## herda marcha.
class_name ProceduralVoice
extends RefCounted

## Bytes por amostra no formato de 16 bits.
const BYTES_PER_SAMPLE: int = 2
## Divisor de milissegundos para segundos.
const MS_PER_SECOND: float = 1000.0

## Falas já sintetizadas, por chave de voz. Sintetizar é barato mas não é de graça, e a
## mesma pessoa fala muitas vezes na mesma sessão.
static var _cache: Dictionary = {}


## Pitch estável de um falante, derivado do nome. Sempre o mesmo, em qualquer sessão.
static func pitch_for(speaker_id: StringName, posture: StringName) -> float:
	var profile: Dictionary = _profile(posture)
	# O hash cai em 0..1 e depois no intervalo de dispersão do perfil: um `ereto` continua
	# soando `ereto`, mas nenhum aldeão soa exatamente como outro.
	var fraction: float = float(absi(String(speaker_id).hash()) % HASH_BUCKETS) / float(HASH_BUCKETS)
	var spread: float = float(profile["spread"])
	return 1.0 + (fraction * 2.0 - 1.0) * spread


## Buckets do hash. Grande o bastante para vinte habitantes não colidirem em pitch.
const HASH_BUCKETS: int = 4096


static func _profile(posture: StringName) -> Dictionary:
	if Params.VOICE_PROFILES.has(posture):
		return Params.VOICE_PROFILES[posture]
	push_warning("Postura sem perfil de voz: %s. Usando o primeiro." % posture)
	return Params.VOICE_PROFILES.values()[0]


## Uma fala inteira, como `AudioStreamWAV`: sílabas separadas por silêncio.
##
## O número de sílabas vem do comprimento do texto, com teto: uma frase de quarenta letras
## não pode virar quarenta sílabas, senão o habitante recita. `VOICE_SYLLABLES_PER_LINE` é
## o teto, e é o que faz toda fala durar mais ou menos o mesmo.
static func line_for(text: String, speaker_id: StringName, posture: StringName) -> AudioStreamWAV:
	# Divisão inteira de propósito: o que se quer é quantas sílabas cabem no comprimento do
	# texto, e sílaba fracionária não existe.
	@warning_ignore("integer_division")
	var syllables: int = clampi(
		text.length() / LETTERS_PER_SYLLABLE, 1, Params.VOICE_SYLLABLES_PER_LINE
	)
	var key: String = "%s|%s|%d" % [speaker_id, posture, syllables]
	if _cache.has(key):
		return _cache[key]

	var stream: AudioStreamWAV = _synthesize(syllables, speaker_id, posture)
	_cache[key] = stream
	return stream


## Letras por sílaba. Não é fonética: é a régua que transforma comprimento de texto em
## duração de fala sem ler o texto.
const LETTERS_PER_SYLLABLE: int = 7


## Costura uma fala a partir do banco da raça.
##
## A escolha das sílabas é semeada pelo nome do falante, então a mesma pessoa dizendo uma
## frase do mesmo tamanho diz sempre as mesmas sílabas — o que soa como sotaque, e não
## como sorteio. Sortear a cada fala soaria aleatório; e aleatório não soa errado, o que é
## exatamente o defeito que ouvido nenhum pega e por isso é o que se tem de decidir aqui.
static func _synthesize(
	syllables: int, speaker_id: StringName, posture: StringName
) -> AudioStreamWAV:
	var bank: Array[AudioStreamWAV] = _bank(posture)
	if bank.is_empty():
		return null

	var rate: int = Params.VOICE_SAMPLE_RATE
	var gap_samples: int = int(float(rate) * float(Params.VOICE_GAP_MS) / MS_PER_SECOND)
	var gap: PackedByteArray = PackedByteArray()
	gap.resize(gap_samples * BYTES_PER_SAMPLE)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = absi(String(speaker_id).hash())

	var data: PackedByteArray = PackedByteArray()
	for index: int in syllables:
		var picked: AudioStreamWAV = bank[rng.randi() % bank.size()]
		data.append_array(picked.data)
		if index < syllables - 1:
			data.append_array(gap)

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


## O banco de uma raça, carregado uma vez por sessão.
##
## Pelo nome, sem registro: `voz/<postura>_<n>.wav`. Uma postura nova ganha voz assim que
## `make audio` gerar o banco dela — nenhuma lista para atualizar aqui.
static func _bank(posture: StringName) -> Array[AudioStreamWAV]:
	if _banks.has(posture):
		return _banks[posture]

	var loaded: Array[AudioStreamWAV] = []
	for index: int in Params.VOICE_BANK_SYLLABLES:
		var path: String = "%s/voz/%s_%d.wav" % [Params.AUDIO_DIR, posture, index]
		if not ResourceLoader.exists(path):
			continue
		var syllable: AudioStreamWAV = ResourceLoader.load(path) as AudioStreamWAV
		if syllable == null:
			continue
		if syllable.format != AudioStreamWAV.FORMAT_16_BITS:
			# A costura é feita nos bytes, e bytes de formatos diferentes não se somam.
			push_warning("Sílaba fora de 16 bits: %s. Confira o import do Godot." % path)
			continue
		loaded.append(syllable)

	if loaded.is_empty():
		push_warning("Banco de voz vazio para a postura %s. Rode `make audio`." % posture)
	_banks[posture] = loaded
	return loaded


static var _banks: Dictionary = {}
