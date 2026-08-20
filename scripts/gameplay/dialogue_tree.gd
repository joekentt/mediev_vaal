## Uma conversa como dado: nós com texto, falante, condições e até quatro escolhas.
##
## É `Resource` pelo mesmo motivo que a agenda de NPC é: **acrescentar conversa não pode
## exigir código**. Escrever um `.tres` novo, apontar um arquétipo para ele, e acabou —
## nenhum `match id_da_conversa` em lugar nenhum, nenhum registro para atualizar.
##
## Um nó é um dicionário:
##
##     {"id", "text", "conditions": [...], "effects": [...], "choices": [...]}
##
## Uma escolha é `{"text", "goto", "conditions": [...], "effects": [...]}`, e `goto` vazio
## encerra a conversa. Uma condição é `{"type", "key", "compare", "value"}` com `type` em
## `flag`, `reputacao` ou `raca`; um efeito é `{"type", "key", "value"}` com `type` em
## `flag` ou `reputacao`.
##
## **Nada aqui toca no `GameState`.** As condições são avaliadas contra um dicionário de
## contexto que o chamador monta. Não é purismo: o `GameState` é autoload, e identificador
## de autoload não existe quando um script de ferramenta compila — a fase 10 já pagou esse
## preço. Com contexto explícito, a prova de diálogo avalia uma árvore inteira sem abrir o
## jogo, e o mesmo código serve aos dois.
class_name DialogueTree
extends Resource

## Tipos de condição e de efeito. São contrato com `tools/gen_dialogues.py`, que reprova
## a geração de um `.tres` que use um tipo fora desta lista.
const TYPE_FLAG: StringName = &"flag"
const TYPE_REPUTATION: StringName = &"reputacao"
const TYPE_RACE: StringName = &"raca"

## Chaves do dicionário de contexto que `evaluate` espera.
const CONTEXT_FLAGS: StringName = &"flags"
const CONTEXT_REPUTATION: StringName = &"reputacao"
const CONTEXT_RACE: StringName = &"raca"

@export var id: StringName = &""
@export var speaker: String = ""
@export var start: StringName = &""
@export var nodes: Array[Dictionary] = []


## Nó pelo identificador. Vazio quando não existe.
func node(node_id: StringName) -> Dictionary:
	for entry: Dictionary in nodes:
		if StringName(entry["id"]) == node_id:
			return entry
	return {}


## Nó inicial já filtrado pelas condições dele.
func opening(context: Dictionary) -> Dictionary:
	var first: Dictionary = node(start)
	if first.is_empty() or not passes(first, context):
		return _first_passing(context)
	return first


## Primeiro nó cujas condições passam. É a saída de emergência de uma árvore cujo nó
## inicial foi barrado por condição — melhor abrir na segunda fala que não abrir.
func _first_passing(context: Dictionary) -> Dictionary:
	for entry: Dictionary in nodes:
		if passes(entry, context):
			return entry
	return {}


## Escolhas visíveis de um nó, na ordem escrita, já filtradas e limitadas ao teto.
##
## O teto é cobrado aqui **e** na geração. Na geração porque é lá que o erro é do autor;
## aqui porque um `.tres` escrito à mão continuaria passando pelo gerador sem passar por
## ninguém.
func choices_for(entry: Dictionary, context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not entry.has("choices"):
		return out
	for choice: Dictionary in entry["choices"]:
		if not passes(choice, context):
			continue
		out.append(choice)
		if out.size() >= Params.DIALOGUE_MAX_CHOICES:
			break
	return out


## O nó ou a escolha passa nas próprias condições?
func passes(entry: Dictionary, context: Dictionary) -> bool:
	if not entry.has("conditions"):
		return true
	for condition: Dictionary in entry["conditions"]:
		if not evaluate(condition, context):
			return false
	return true


## Avalia uma condição contra o contexto. Todas as comparações passam pelo mesmo lugar,
## para um `>=` novo não precisar de um tipo de condição novo.
static func evaluate(condition: Dictionary, context: Dictionary) -> bool:
	var kind: StringName = StringName(condition["type"])
	var wanted: Variant = condition["value"]
	var compare: String = String(condition.get("compare", "=="))

	if kind == TYPE_FLAG:
		var flags: Dictionary = context.get(CONTEXT_FLAGS, {})
		return _compare(flags.get(condition["key"], false), compare, wanted)
	if kind == TYPE_REPUTATION:
		var reputation: Dictionary = context.get(CONTEXT_REPUTATION, {})
		return _compare(int(reputation.get(condition["key"], 0)), compare, wanted)
	if kind == TYPE_RACE:
		return _compare(context.get(CONTEXT_RACE, &""), compare, wanted)

	push_warning("Condição de diálogo com tipo desconhecido: %s" % kind)
	return false


static func _compare(left: Variant, compare: String, right: Variant) -> bool:
	if compare == "!=":
		return left != right
	if compare == ">=":
		return left >= right
	if compare == "<=":
		return left <= right
	if compare == ">":
		return left > right
	if compare == "<":
		return left < right
	return left == right


## Efeitos de um nó ou escolha, como lista. Quem os aplica é o runner: este arquivo não
## conhece `GameState` e não vai conhecer.
static func effects_of(entry: Dictionary) -> Array:
	return entry.get("effects", [])
