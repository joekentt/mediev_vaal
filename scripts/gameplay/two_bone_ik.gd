## IK analítica de duas juntas — a base de toda perna e todo braço do projeto.
##
## Duas juntas é o caso em que a resposta é fechada: dados o comprimento da coxa e o da
## canela, a posição do joelho é a interseção de duas esferas, e essa interseção é um
## círculo. O vetor de polo escolhe **onde nesse círculo** o joelho fica — é o que impede
## a perna de dobrar para trás. Não há iteração, não há convergência, não há custo que
## dependa de quão longe o alvo está: uma raiz quadrada e dois produtos vetoriais.
##
## O solver é puro: recebe posições e devolve posições, no espaço que o chamador quiser,
## desde que seja o mesmo para todas. Quem casa isso com um `Skeleton3D` é
## `ProceduralLocomotion`, e é lá que mora o único conhecimento sobre ossos.
class_name TwoBoneIK
extends RefCounted

## Folga deixada quando o alvo está mais longe que o membro esticado. Sem ela, o
## triângulo degenera exatamente no limite e a direção do joelho vira indefinida — a
## perna pisca entre dois lados no frame em que o passo chega ao fim do alcance.
const REACH_MARGIN: float = 0.999
## Idem para o alvo perto demais, onde o membro teria de se dobrar sobre si mesmo.
const FOLD_MARGIN: float = 1.001
## Abaixo disto dois vetores contam como paralelos e o produto vetorial não serve de eixo.
const PARALLEL_EPSILON: float = 0.0001


## Posição da junta do meio (joelho, cotovelo) para alcançar `target` a partir de `root`.
##
## `upper` e `lower` são os comprimentos dos dois segmentos; `pole` é a direção para a
## qual a junta aponta — à frente, no caso do joelho, e para trás no do cotovelo.
## O alvo é clampeado ao alcance, então o membro estica mas nunca se desmonta.
static func solve(
	root: Vector3,
	target: Vector3,
	upper: float,
	lower: float,
	pole: Vector3
) -> Vector3:
	var to_target: Vector3 = target - root
	var distance: float = to_target.length()
	if distance < PARALLEL_EPSILON:
		# Alvo em cima da raiz: sem direção, devolve a junta deslocada pelo polo, que é
		# a única resposta que não é NAN.
		return root + pole.normalized() * upper

	var reach: float = (upper + lower) * REACH_MARGIN
	var fold: float = absf(upper - lower) * FOLD_MARGIN
	var clamped: float = clampf(distance, fold, reach)
	var direction: Vector3 = to_target / distance

	# Lei dos cossenos: a projeção da junta sobre o eixo raiz→alvo.
	var along: float = (clamped * clamped + upper * upper - lower * lower) / (2.0 * clamped)
	var offset_squared: float = upper * upper - along * along
	var offset: float = sqrt(maxf(0.0, offset_squared))

	return root + direction * along + _bend_axis(direction, pole) * offset


## Direção perpendicular ao eixo do membro, no plano definido pelo polo.
##
## Projetar o polo fora do eixo é o que mantém o joelho para a frente mesmo quando a
## perna gira: usar o polo cru faria o plano de dobra girar junto com o alvo.
static func _bend_axis(direction: Vector3, pole: Vector3) -> Vector3:
	var projected: Vector3 = pole - direction * direction.dot(pole)
	if projected.length() < PARALLEL_EPSILON:
		# Polo paralelo ao membro: escolhe qualquer perpendicular estável, para não
		# devolver zero e colapsar a junta sobre o eixo.
		var fallback: Vector3 = direction.cross(Vector3.UP)
		if fallback.length() < PARALLEL_EPSILON:
			fallback = direction.cross(Vector3.RIGHT)
		return fallback.normalized()
	return projected.normalized()


## Rotação mínima que leva `from` a `to`. Devolve identidade quando já coincidem.
##
## `Quaternion(from, to)` da engine faz isto, mas devolve lixo quando os vetores são
## opostos ou nulos — e "opostos" acontece de verdade aqui, no braço que passa pela
## vertical. Este envelope trata os dois casos em vez de deixar um NAN entrar no esqueleto
## e apagar o personagem inteiro da tela.
static func swing(from: Vector3, to: Vector3) -> Quaternion:
	var a: Vector3 = from.normalized()
	var b: Vector3 = to.normalized()
	if a.length_squared() < PARALLEL_EPSILON or b.length_squared() < PARALLEL_EPSILON:
		return Quaternion.IDENTITY
	var dot: float = clampf(a.dot(b), -1.0, 1.0)
	if dot > 1.0 - PARALLEL_EPSILON:
		return Quaternion.IDENTITY
	if dot < -1.0 + PARALLEL_EPSILON:
		var axis: Vector3 = a.cross(Vector3.UP)
		if axis.length() < PARALLEL_EPSILON:
			axis = a.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a, b)
