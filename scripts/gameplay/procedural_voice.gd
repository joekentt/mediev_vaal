## Voz por síntese: sílabas curtas, sem gravação e sem texto lido.
##
## É a mesma escolha estética da locomoção da fase 6. A fala não é atuada, é **sugerida** —
## e a 900 triângulos por rosto, com olho e boca sendo planos afundados na face, uma voz
## atuada prometeria uma fidelidade que a cara não entrega. O que se quer é o ritmo de
## alguém falando, não as palavras.
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

const HALF: float = 0.5
const MIN_LENGTH: float = 0.001
## Amplitude máxima de uma amostra de 16 bits.
const SAMPLE_PEAK: float = 32767.0
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


static func _synthesize(
	syllables: int, speaker_id: StringName, posture: StringName
) -> AudioStreamWAV:
	var profile: Dictionary = _profile(posture)
	var rate: int = Params.VOICE_SAMPLE_RATE
	var syllable_samples: int = int(float(rate) * float(Params.VOICE_SYLLABLE_MS) / MS_PER_SECOND)
	var gap_samples: int = int(float(rate) * float(Params.VOICE_GAP_MS) / MS_PER_SECOND)
	var total: int = syllables * syllable_samples + maxi(syllables - 1, 0) * gap_samples

	# Um gerador por falante, semeado pelo nome: o desenho da fala é dele e não muda.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = absi(String(speaker_id).hash())

	var base: float = float(profile["base_hz"]) * pitch_for(speaker_id, posture)
	var brightness: float = float(profile["brightness"])
	var wobble: float = float(profile["wobble"])

	var data: PackedByteArray = PackedByteArray()
	data.resize(total * BYTES_PER_SAMPLE)
	var cursor: int = 0

	for syllable: int in syllables:
		# Cada sílaba tem o seu próprio pitch, em torno do do falante. Sem essa variação a
		# fala vira um bipe repetido, que é como um rádio quebrado e não como alguém falando.
		var hz: float = base * (
			1.0 + rng.randf_range(-Params.VOICE_PITCH_JITTER, Params.VOICE_PITCH_JITTER)
		)
		for index: int in syllable_samples:
			var travel: float = float(index) / float(maxi(syllable_samples, 1))
			var value: float = _wave(travel, hz, wobble, brightness)
			cursor = _write(data, cursor, value * _envelope(travel))
		for _silence: int in gap_samples:
			if syllable < syllables - 1:
				cursor = _write(data, cursor, 0.0)

	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


## Uma sílaba: fundamental mais parciais, com o pitch escorregando dentro dela.
##
## O escorregão (`wobble`) é o que faz a sílaba soar como boca e não como oscilador — uma
## vogal humana nunca fica parada na mesma frequência por cem milissegundos.
static func _wave(travel: float, hz: float, wobble: float, brightness: float) -> float:
	var slide: float = hz + sin(travel * PI) * wobble
	var phase: float = travel * float(Params.VOICE_SYLLABLE_MS) / MS_PER_SECOND * slide * TAU
	var value: float = sin(phase)
	# Parciais ímpares, com peso caindo: é o que dá corpo ao som sem virar serra.
	for harmonic: int in range(2, Params.VOICE_HARMONICS + 1):
		value += sin(phase * float(harmonic)) * brightness / float(harmonic)
	return value / float(Params.VOICE_HARMONICS)


## Envelope de ataque e queda. Sem ele, cada sílaba começa e termina num estalo — a
## descontinuidade da onda é audível e soa como falha de áudio, não como fala.
static func _envelope(travel: float) -> float:
	if travel < Params.VOICE_ATTACK:
		return travel / maxf(Params.VOICE_ATTACK, MIN_LENGTH)
	var release_start: float = 1.0 - Params.VOICE_RELEASE
	if travel > release_start:
		return (1.0 - travel) / maxf(Params.VOICE_RELEASE, MIN_LENGTH)
	return 1.0


static func _write(data: PackedByteArray, cursor: int, value: float) -> int:
	var sample: int = int(clampf(value, -1.0, 1.0) * SAMPLE_PEAK)
	data.encode_s16(cursor, sample)
	return cursor + BYTES_PER_SAMPLE
