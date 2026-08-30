## Agenda diária de um arquétipo: o que fazer, onde, e a que horas.
##
## É `Resource` e não código por um motivo prático: trocar a rotina de um povo inteiro tem
## de ser trocar um `.tres`, não recompilar. É a mesma escolha dos perfis de marcha da
## fase 6 — `if arquetipo == ...` espalhado pelo controlador seria a forma garantida de
## tornar impossível acrescentar um quarto arquétipo.
##
## Os blocos referenciam **nomes de marcador**, nunca coordenadas. Dois nomes são
## especiais e resolvidos por NPC: `casa` vira a casa daquele habitante e `trabalho` vira o
## posto dele. Todo o resto é o nome literal de um `Marker3D` que a fase 8 gerou — `praca`,
## `poco`, `taverna`, `portao`. É isso que faz a mesma rotina funcionar em qualquer seed de
## cidade: nada aqui sabe onde a praça ficou desta vez.
##
## Os blocos cobrem as 24 horas sem buraco, e a hora final pode passar de 24 para o bloco
## do sono atravessar a meia-noite. Um buraco na cobertura deixaria o NPC sem ordem e ele
## congelaria no lugar às 3 da manhã — defeito que só aparece quando alguém deixa o jogo
## rodando sozinho.
class_name NPCSchedule
extends Resource

## Nome do arquétipo. Serve para escolher a fala e para o relatório da prova.
@export var archetype: StringName = &""

## Blocos `{"start": float, "end": float, "marker": StringName, "state": StringName}`.
@export var blocks: Array[Dictionary] = []


## Bloco que vale numa hora do dia. Devolve vazio só se a agenda estiver vazia.
##
## A hora é normalizada para 0..24 e testada também somada de 24, porque o bloco do sono
## termina depois da meia-noite: quem dorme das 21 às 6 tem `end` igual a 30.
func block_for(hour: float) -> Dictionary:
	if blocks.is_empty():
		return {}
	var clock: float = fposmod(hour, HOURS_PER_DAY)
	for block: Dictionary in blocks:
		var start: float = float(block["start"])
		var finish: float = float(block["end"])
		if clock >= start and clock < finish:
			return block
		if clock + HOURS_PER_DAY >= start and clock + HOURS_PER_DAY < finish:
			return block
	# Nenhum bloco cobre esta hora: a agenda tem um buraco. Devolver o primeiro mantém o
	# NPC andando em vez de o congelar, e o aviso diz onde consertar.
	push_warning("Agenda '%s' não cobre a hora %.1f." % [archetype, clock])
	return blocks[0]


const HOURS_PER_DAY: float = 24.0
