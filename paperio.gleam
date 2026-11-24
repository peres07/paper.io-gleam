// Disputa de Território
//
// Jogo multijogador inspirado no Paper.io para o Trabalho 01.
//
// Autores: Bruno Rafael Comin Scheffel e José Luis Peres de Sousa
//
// Regras
//
// - Dois jogadores. Cada jogador começa com uma base própria
//   em um lado do tabuleiro.
// - Ao sair do próprio território, o jogador deixa um rastro. Ao retornar
//   a qualquer território próprio, inclusive uma ilha criada pela expansão, o rastro e as
//   casas cercadas são conquistados.
// - A base inicial de cada jogador é permanente e não pode ser conquistada
//   pelo adversário. Os demais territórios podem ser conquistados por ambos.
// - Atravessar o rastro adversário elimina seu dono. O jogador eliminado
//   perde o rastro, os poderes guardados e o efeito de velocidade, mas
//   mantém seus territórios e reaparece após 2 segundos em sua base.
// - Encostar diretamente no personagem adversário não elimina.
// - A cada 8 segundos, um poder aleatório pode aparecer em uma casa
//   sem jogador. Podem existir no máximo dois poderes no mapa.
// - Os poderes são coletados ao passar pela casa e ficam guardados
//   até serem utilizados.
// - Expansão: conquista as casas de uma área 3x3 ao redor do personagem,
//   exceto as pertencentes à base adversária.
// - Velocidade: aumenta a velocidade do jogador por 4 segundos.
// - A partida dura 60 segundos
// - Cada casa do território vale 1 ponto. Vence quem possuir mais
//   territórios ao final da partida, podendo haver empate.
//
// Controles
//
// - Enter: começa a partida (na abertura) ou joga novamente (no resultado).
// - Setas: movimentam o personagem uma casa nas quatro direções.
// - Tecla 1: utiliza um poder de expansão armazenado.
// - Tecla 2: utiliza um poder de velocidade armazenado.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import sgleam/check
import sgleam/color.{type Color}
import sgleam/env.{type Env}
import sgleam/fill
import sgleam/image.{type Image}
import sgleam/key
import sgleam/mworld
import sgleam/random.{type Generator}
import sgleam/style

// ----------------------------------------------------------------------
// Constantes
// ----------------------------------------------------------------------

/// Quantidade de casas em cada lado da grade.
const tamanho = 20

/// Lado de uma casa, em pixels.
const lado_casa = 20

/// Quantidade de tiques por segundo.
const tiques_por_segundo = 10

/// Duração da partida, em tiques (60 segundos).
const duracao = 600

/// Largura da tela, em pixels.
const largura = 400

/// Altura da tela, em pixels.
const altura = 520

/// Velocidade da cobra
const velocidade_cobra = 2.0

/// Velocidade extra da cobra
const velocidade_boost = 3.0

/// Tempo de velocidade extra
const boost_tempo = 40

/// Delay poder (8 segundos)
const delay_poder = 80

// ----------------------------------------------------------------------
// Tipos de dados
// ----------------------------------------------------------------------

/// Uma casa da grade. *lin* e *col* estão entre 0 e `tamanho - 1`; a casa
/// Posicao(0, 0) fica no canto superior esquerdo.
pub type Posicao {
  Posicao(lin: Int, col: Int)
}

/// A direção de um movimento.
pub type Direcao {
  Cima
  Baixo
  Esquerda
  Direita
}

/// Uma casa do mapa. *posicao* indica sua localização na grade e *dono*
/// indica o número do jogador que controla a casa, ou None se é neutra.
pub type Casa {
  Casa(posicao: Posicao, dono: Option(Int))
}

/// Os tipos de poderes que podem ser utilizados pelos jogadores.
pub type TipoPoder {
  Expansao
  Velocidade
}

pub type ImagensPoderes {
  ImagensPoderes(velocidade: Image, expansao: Image)
}

/// Um poder disponível no mapa. *tipo* indica o efeito do poder e
/// *posicao* indica a casa em que ele pode ser coletado.
pub type PoderNoMapa {
  PoderNoMapa(tipo: TipoPoder, posicao: Posicao)
}

/// Um jogador da partida. *id* identifica o jogador, *posicao* indica sua
/// casa atual, *direcao* indica para onde ele se move e *rastro*
/// contém as casas percorridas fora do próprio território.
pub type Jogador {
  Jogador(
    id: Int,
    posicao: Posicao,
    direcao: Direcao,
    rastro: List(Posicao),
    base: List(Posicao),
    // Poderes coletados e ainda não utilizados.
    poderes_guardados: List(TipoPoder),
    // Tiques restantes do efeito de velocidade.
    velocidade_extra: Int,
    // Velocidade de movimento em casas por segundo.
    velocidade: Float,
    // Tiques restantes até o jogador reaparecer.
    reaparecimento: Int,
  )
}

/// Uma partida em andamento. *mapa* contém as casas e seus proprietários,
/// *jogadores* guarda os participantes e *poderes* contém os poderes
/// disponíveis. *tiques* conta o tempo desde o início da partida e
/// *proximo_poder* indica os tiques restantes até surgir outro poder.
pub type Partida {
  Partida(
    mapa: List(Casa),
    jogadores: List(Jogador),
    poderes: List(PoderNoMapa),
    tiques: Int,
    proximo_poder: Int,
    placares: List(Placar),
  )
}

/// A pontuação de um jogador. *jogador* indica seu número e *casas*
/// representa a quantidade de casas que ele controla.
pub type Placar {
  Placar(jogador: Int, casas: Int)
}

/// O estado do jogo. Todos os estados guardam o gerador de números
/// aleatórios utilizado durante a partida.
pub type Estado {
  /// Antes da primeira partida.
  Abertura(gerador: random.Generator, imagens: ImagensPoderes)
  /// Durante uma partida.
  EmPartida(
    gerador: random.Generator,
    imagens: ImagensPoderes,
    partida: Partida,
  )
  /// Depois de uma partida, com a pontuação dos jogadores.
  Resultado(
    gerador: random.Generator,
    imagens: ImagensPoderes,
    placares: List(Placar),
  )
}

// ----------------------------------------------------------------------
// Funções auxiliares
// ----------------------------------------------------------------------

/// Aplica a função *f* apenas ao jogador com *id* igual a *jogador_id*.
fn atualiza_jogador(
  jogadores: List(Jogador),
  jogador_id: Int,
  f: fn(Jogador) -> Jogador,
) -> List(Jogador) {
  list.map(jogadores, fn(j) {
    case j.id == jogador_id {
      True -> f(j)
      False -> j
    }
  })
}

pub fn atualiza_jogador_examples() {
  let j = cria_jogador(1)
  let novo = Jogador(..j, direcao: Direita)

  // Se achar o id, substitui
  check.eq(atualiza_jogador([j], 1, fn(_) { novo }), [novo])

  // Se não achar, retorna como estava
  check.eq(atualiza_jogador([j], 2, fn(_) { novo }), [j])
  check.eq(atualiza_jogador([], 1, fn(_) { novo }), [])
}

/// Procura um jogador na lista pelo seu *id*.
fn busca_jogador(
  jogadores: List(Jogador),
  jogador_id: Int,
) -> Result(Jogador, Nil) {
  list.find(jogadores, fn(j) { j.id == jogador_id })
}

pub fn busca_jogador_examples() {
  let j1 = cria_jogador(1)
  let j2 = cria_jogador(2)
  check.eq(busca_jogador([j1, j2], 1), Ok(j1))
  check.eq(busca_jogador([j1, j2], 2), Ok(j2))

  // Não tem jogador com id = 3
  check.eq(busca_jogador([j1, j2], 3), Error(Nil))

  // Não tem jogador criado ainda
  check.eq(busca_jogador([], 1), Error(Nil))
}

// ----------------------------------------------------------------------
// Mundo
// ----------------------------------------------------------------------

pub fn smain() {
  mworld.create_from(inicio, min: 2, max: 2, to_image: desenha)
  |> mworld.tick_rate(tiques_por_segundo)
  |> mworld.on_tick(tique)
  |> mworld.on_key_down(tecla)
}

/// Cria a abertura com o gerador aleatório e as imagens
/// dos poderes. A partida sempre terá dois jogadores.
fn inicio(env: Env, jogadores: List(mworld.Player)) -> Estado {
  Abertura(env.random(env), carrega_imagens())
}

fn carrega_imagens() -> ImagensPoderes {
  ImagensPoderes(
    velocidade: image.bitmap_data_uri(
      "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAcCAYAAAByDd+UAAAEAUlEQVR4AbyVa2hcVRDH/7N7d5NN1jzKxmibR9WmCUpbLQRBipgS001SSVWwUSp+7KdoP/hBClK/iM+2+ChFEJRKPqgfVARBqQasDUkLicQIpShVmlfTtJvcx+597R3npg3ktTe7bezhzM65Z/bM78yZM/eGcIfbugL5K4T57N0PcB8qkKOtG5D7a2Ko39IKJ/s+bNTk4GFdgALbACX2Ipz0UWSN32kPRv83IA81boRSegiu+zpbxjRgfpoL5s/fVoQ8+mAdvOib4GwPW2rMc81j2I1J33EuuWUgDz1SD6Wul5X4AVhGObv6qTBb/UTwcsH8+YKB3PeEwqPNzYjXnIGT2QVjXGFHGwp53peUxHXfaZAUBOSRbZWophcQ3fQDLK0W+hhEp9hO92LOGQ4CLdjyAjKD5o8wcs8hKGVHYV5LwJgA26pDrtYXCnnf0nNSDAteA/SaQL+YMfroNpTce0Ru48vIzCSQuQp2DJCljoP5cymDSwGMJaZAoEQWQuPOx1BU9Z7UWTfSVytg+WliIGt7iMQuo7w+yue3dvBgw14+1/QUDzR28eDWfU5fVZJPo3oJTR4CgRja3olY7ScIl+yGMRmbh7EnywAqLiPEEjtAkWPw6CQodALsnZDD/1hy+lHYVg/DxSYsa6sCZf8kO+5BvK4X0XgTtH8VmBLZTdi8D1IIFC6Tcd28MERTLTuZGmSuxD3POo4ijIhtSV8B5H7EvN9q3oFrv8tzl+I8dR6sjTPbmi+eFDizDw5HxRGJLHTZpq15chIT5Dp7lXZ8Qy0S44L5pl4BxGxkB/TJetbGBmj2wi+Y/ftncXIaxtRPSF/5EdbcBURKPSS2Q/J6w42/AUu1ODMzQJ7bTh04e8Ow8je0fIo6nIFwMrs/lMy2UFu2VfSTIm0iSSq/r5s2NAxS+RYP6WnATUvaspCoNTZT3ztsH0QSfyz3ufh5BXCxcfFYbiyBijpRurENWVPxi549Vwpfvc62+gXBOhxtw59EkLNdvHLpOG8gzt3fgJLEAZBSDf2yvK8dwEzNkK1+EHIyb6ENf60F89F5AblvczGiiX2IxHdJHsNsG0BmOuXZ2muImB9KzsYIwZH5MF/yAiIWexjFFftha2VsXoNcqmny0l3hf5xT1IJZFNDWBPLw5grclXiGXWsnGxNZua3D5BqPU6t7hg5CzrUAmvw1EMhvIAQr0gwj9ZJEpSM99R1ZRjfacVHW3lIPBKK9qRLMPbBTROmJz8jVX6VOXMw3X6vtKBjI5rNw9Yc8Uz0OXX+b9iDvr8JqMH8uJ1D7NV4FU3tePrBHVE07SV2Y8BfcruQExnVdhWu+Atv4uvJpFHQTEdByAqW2LGo1RnwdsL5g038AAAD//1nzxfoAAAAGSURBVAMAzd/ISM+0u1wAAAAASUVORK5CYII=",
    ),
    expansao: image.bitmap_data_uri(
      "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAcCAYAAAByDd+UAAAELUlEQVR42r2Wz29UVRTHP+feOzOvM9OWRkAwREOIClGKweCPEEPUja7YGN0Q/wzjgo07ExP1n3ChIZHEjQs1JvVHAKMUqgRigj8o0hZop/PzvXfvPS5m6MxIp5UGfcnb3Pfe/dxzvud83wFAVYX//hIAUVUREX3v1JePJNXqwbTVQiUIYeBVu5X9HSHG+M3cXKwtr56f+fDkX4AIIO+fmtlLkR+ScnnK5znWWhBBAAU0xnvGKeCM4beFBc7Mzt5IyubI5++8Pe8AjdZPl8sTU83VWladnLDFpIQYgzGGPM2o3bqNbgFYMIZx50KpXN2Vp+2ngGsOAGO9z3NNymO2MlG1qkoMkVa9TqfZ7guwhSvEiAavEWI30d2UiYiILXTFyjoZ9eUVvPeICMYIKCOjFAHdKAUia+c1g+vGGDRG6ssrhBAwvbT6oPgROkZVch8H99zw6gNVMcaQpVk/MhGy3DNZLjFVGSNGvQtWKRXZOVkhzT3mX0CHIsyznE6r3YtW6OSe7RMVThx7mlcPP05UXdPSiJD5wHOPPcybLx7h0d0P0ErzTaFrQDGGVr1Bp9XGOUsn8+ycrPD60WkqYyWsMVhrQLqSiHShRWexVjj+zBPs37NjU6j5p/rWmAHYIapJCQ2eqErmPbmP5D6Q+0jmPUH72h5/tgfNcuwIqBuii9DOcx6crPZgRdI8UHKWUsHx0NQE2msR6elbTUqoKjEqVrqRcvZnLl1bZHwsGQ0UEXwI7No2zmvPH6SaFMl8wBrBx8i2SsKJY4fRno46UO3eB4wRYowYY7pQ4OrCMv8M1Aw6ax4iLxzYy0SlTCcbrjpV0F6z6dqarq31Dx1x1vDSk/swRu7qTzNkRdYw88tVao0WSdERhzbbtKdRVZw15D7yxcVfiVHv+s4Nv2xZqDX45LsLvHF0mvGx0pqGtxotPjt3CUXXNEzzwMvT+9i3eztZ5rtVDJw+O8fl+SXGxxJanQ2qNKqSFBw3V5t8/O0F6u2UorOAkuaeGyt1lmpNFmtNlmpNFlbqNNOsb3/A6TNzXLl+k0qpOJTu9dtiBFSsw4hQcJaCMwO3xUp/i9Nn5rh8/SblYoEwwlzNKH/sQ2eptzv4GAkhdk28d3d7M+BD5NMBWNzAyd2oB3egtxstPvr6R4zpeqsOPC86y/dXfuenq/Ms1pqbwjYE9jd11NspimLNcEKMCK00p9HJKBXcprBNgXeq1xoBZN3/oRHBGlm3QDYE9ptY1h0XNj7UOmvCuodwAGmaUq1W1VnL/ZoXu0bSnSDiwI/UAcxcmDUH9x+QCedCiHG0rdwTURERrvz5R0CMNb2OcICspun5cxcvLiXlyo4Ywv2ZeqVr5hhj1aeLWZbP3hl/BERfeevdPVoqHvKdjoDd4vA7OK51D+6SquaN1fNffXByfqBA/r9R/2++TjJoeEgdIQAAAABJRU5ErkJggg==",
    ),
  )
}

/// Desenha o *estado* do ponto de vista de *jogador*.
fn desenha(estado: Estado, jogador: mworld.Player) -> Image {
  tela(estado, mworld.player_index(jogador))
}

/// Trata a tecla e a identificação do jogador
/// para processar os comandos do jogo.
fn tecla(estado: Estado, jogador: mworld.Player, evento: key.Event) -> Estado {
  processa_tecla(estado, mworld.player_index(jogador), evento)
}

// ----------------------------------------------------------------------
// Início da partida
// ----------------------------------------------------------------------

/// Produz a lista dos números de *inicio* até *fim*, inclusive. Produz a
/// lista vazia se *inicio* é maior que *fim*.
pub fn sequencia(inicio: Int, fim: Int) -> List(Int) {
  case inicio > fim {
    True -> []
    False -> [inicio, ..sequencia(inicio + 1, fim)]
  }
}

pub fn sequencia_examples() {
  check.eq(sequencia(3, 2), [])
  check.eq(sequencia(3, 3), [3])
  check.eq(sequencia(0, 4), [0, 1, 2, 3, 4])

  check.eq(sequencia(-2, 0), [-2, -1, 0])
  check.eq(sequencia(0, 0), [0])
}

/// Produz a lista de todas as casas da grade, linha por linha.
pub fn todas_as_casas() -> List(Posicao) {
  list.flat_map(sequencia(0, tamanho - 1), fn(lin) {
    list.map(sequencia(0, tamanho - 1), fn(col) { Posicao(lin, col) })
  })
}

pub fn todas_as_casas_examples() {
  check.eq(list.length(todas_as_casas()), 400)
  check.eq(list.first(todas_as_casas()), Ok(Posicao(0, 0)))
  check.eq(list.last(todas_as_casas()), Ok(Posicao(19, 19)))
}

/// Cria o mapa com todas as casas neutras.
pub fn cria_mapa() -> List(Casa) {
  list.map(todas_as_casas(), fn(posicao) { Casa(posicao, None) })
}

pub fn cria_mapa_examples() {
  let mapa = cria_mapa()
  check.eq(list.length(mapa), tamanho * tamanho)
  check.eq(list.first(mapa), Ok(Casa(Posicao(0, 0), None)))
  check.eq(list.last(mapa), Ok(Casa(Posicao(tamanho - 1, tamanho - 1), None)))
  check.eq(list.count(mapa, fn(casa) { casa.dono != None }), 0)
}

pub fn base_inicial(id: Int) -> List(Posicao) {
  let colunas = case id {
    1 -> sequencia(0, 2)
    2 -> sequencia(tamanho - 3, tamanho - 1)
    _ -> []
  }

  let linhas = case id {
    1 -> sequencia(tamanho - 3, tamanho - 1)
    2 -> sequencia(0, 2)
    _ -> []
  }

  list.flat_map(linhas, fn(lin) {
    list.map(colunas, fn(col) { Posicao(lin, col) })
  })
}

pub fn base_inicial_examples() {
  check.eq(list.length(base_inicial(1)), 9)
  check.eq(list.length(base_inicial(2)), 9)
  check.eq(list.contains(base_inicial(1), Posicao(17, 2)), True)
  check.eq(list.contains(base_inicial(2), Posicao(2, 17)), True)

  check.eq(base_inicial(3), [])
}

pub fn cria_jogador(id: Int) -> Jogador {
  let base = base_inicial(id)

  let posicao = case id {
    1 -> Posicao(tamanho - 2, 1)
    _ -> Posicao(1, tamanho - 2)
  }

  Jogador(
    id: id,
    posicao: posicao,
    direcao: direcao_inicial(id),
    rastro: [],
    base: base,
    poderes_guardados: [],
    velocidade_extra: 0,
    velocidade: velocidade_cobra,
    reaparecimento: 0,
  )
}

pub fn cria_jogador_examples() {
  let j1 = cria_jogador(1)
  let j2 = cria_jogador(2)
  check.eq(j1.posicao, Posicao(tamanho - 2, 1))
  check.eq(j2.posicao, Posicao(1, tamanho - 2))
  check.eq(j1.base, base_inicial(1))
  check.eq(j1.rastro, [])
  check.eq(j1.velocidade, velocidade_cobra)
}

/// Define a direção inicial baseada no **id** do jogador.
pub fn direcao_inicial(id: Int) -> Direcao {
  case id {
    1 -> Cima
    _ -> Baixo
  }
}

pub fn direcao_inicial_examples() {
  check.eq(direcao_inicial(1), Cima)
  check.eq(direcao_inicial(2), Baixo)
  check.eq(direcao_inicial(0), Baixo)
}

pub fn nova_partida() -> Partida {
  let base1 = base_inicial(1)
  let base2 = base_inicial(2)

  let mapa =
    list.map(cria_mapa(), fn(casa) {
      let dono = case
        list.contains(base1, casa.posicao),
        list.contains(base2, casa.posicao)
      {
        True, _ -> Some(1)
        False, True -> Some(2)
        _, _ -> None
      }

      Casa(..casa, dono: dono)
    })

  Partida(
    mapa: mapa,
    jogadores: [cria_jogador(1), cria_jogador(2)],
    poderes: [],
    tiques: 0,
    proximo_poder: delay_poder,
    placares: [],
  )
  |> atualizar_placares
}

pub fn nova_partida_examples() {
  let p = nova_partida()

  check.eq(list.length(p.mapa), tamanho * tamanho)
  check.eq(p.jogadores, [cria_jogador(1), cria_jogador(2)])
  check.eq(p.placares, [Placar(1, 9), Placar(2, 9)])

  check.eq(dono_da_casa(p.mapa, cria_jogador(1).posicao), Some(1))
  check.eq(dono_da_casa(p.mapa, cria_jogador(2).posicao), Some(2))
  check.eq(dono_da_casa(p.mapa, Posicao(5, 5)), None)

  check.eq(p.poderes, [])

  check.eq(p.tiques, 0)
  check.eq(p.proximo_poder, delay_poder)
}
// ----------------------------------------------------------------------
// Teclas
// ----------------------------------------------------------------------

/// Verifica se duas direções são opostas entre si.
pub fn sao_opostas(dir1: Direcao, dir2: Direcao) -> Bool {
  case dir1, dir2 {
    Cima, Baixo | Baixo, Cima -> True
    Esquerda, Direita | Direita, Esquerda -> True
    _, _ -> False
  }
}

pub fn sao_opostas_examples() {
  check.eq(sao_opostas(Cima, Baixo), True)
  check.eq(sao_opostas(Baixo, Cima), True)
  check.eq(sao_opostas(Esquerda, Direita), True)
  check.eq(sao_opostas(Cima, Direita), False)
  check.eq(sao_opostas(Cima, Cima), False)
}

/// Troca a direção do jogador correspondente
fn guardar_direcao(
  partida: Partida,
  jogador_id: Int,
  nova_direcao: Direcao,
) -> Partida {
  let jogadores =
    atualiza_jogador(partida.jogadores, jogador_id, fn(j) {
      case j.reaparecimento == 0 && !sao_opostas(j.direcao, nova_direcao) {
        True -> Jogador(..j, direcao: nova_direcao)
        False -> j
      }
    })

  Partida(..partida, jogadores: jogadores)
}

pub fn guardar_direcao_examples() {
  let j = cria_jogador(1)
  let p = Partida(..nova_partida(), jogadores: [j])

  // Troca a direção
  check.eq(guardar_direcao(p, 1, Direita).jogadores, [
    Jogador(..j, direcao: Direita),
  ])

  // Não deixa ir para a direção contrária
  check.eq(guardar_direcao(p, 1, Baixo), p)

  let esperando = Partida(..p, jogadores: [Jogador(..j, reaparecimento: 5)])

  // Não altera a direção se o jogador estiver morto
  check.eq(guardar_direcao(esperando, 1, Direita), esperando)
}

/// Devolve a direção que corresponde a *tecla* clicada.
/// Devolve None se *tecla* não é uma seta.
pub fn direcao(tecla: key.Event) -> Option(Direcao) {
  case tecla {
    key.ArrowUp -> Some(Cima)
    key.ArrowDown -> Some(Baixo)
    key.ArrowLeft -> Some(Esquerda)
    key.ArrowRight -> Some(Direita)
    _ -> None
  }
}

pub fn direcao_examples() {
  check.eq(direcao(key.ArrowUp), Some(Cima))
  check.eq(direcao(key.ArrowDown), Some(Baixo))
  check.eq(direcao(key.ArrowLeft), Some(Esquerda))
  check.eq(direcao(key.ArrowRight), Some(Direita))
  check.eq(direcao(key.Enter), None)
}

pub fn processa_tecla(estado: Estado, numero: Int, tecla: key.Event) -> Estado {
  case estado, tecla {
    Abertura(gerador, imagens), key.Enter ->
      EmPartida(gerador, imagens, nova_partida())
    Resultado(gerador, imagens, _), key.Enter ->
      Abertura(gerador, imagens)
    EmPartida(gerador, imagens, partida), key.Char("1") ->
      EmPartida(gerador, imagens, ativar_poder(partida, numero, Expansao))
    EmPartida(gerador, imagens, partida), key.Char("2") ->
      EmPartida(gerador, imagens, ativar_poder(partida, numero, Velocidade))
    EmPartida(gerador, imagens, partida), _ ->
      case direcao(tecla) {
        Some(dir) ->
          EmPartida(gerador, imagens, guardar_direcao(partida, numero, dir))
        None -> estado
      }
    _, _ -> estado
  }
}

pub fn processa_tecla_examples() {
  let g = random.new(0)
  let img = ImagensPoderes(velocidade: image.empty, expansao: image.empty)
  let abertura = Abertura(g, img)

  // Enter na abertura -> nova partida.
  check.eq(
    processa_tecla(abertura, 1, key.Enter),
    EmPartida(g, img, nova_partida()),
  )

  // Enter no resultado -> volta para a abertura.
  check.eq(processa_tecla(Resultado(g, img, []), 1, key.Enter), abertura)

  // Setas não fazem nada na abertura
  check.eq(processa_tecla(abertura, 1, key.ArrowUp), abertura)
}

// ----------------------------------------------------------------------
// Tiques
// ----------------------------------------------------------------------

/// Avança o tempo apenas quando há uma partida em andamento.
pub fn tique(estado: Estado) -> Estado {
  case estado {
    EmPartida(gerador, imagens, partida) -> avanca(gerador, imagens, partida)
    _ -> estado
  }
}

pub fn tique_examples() {
  let g = random.new(0)
  let img = ImagensPoderes(velocidade: image.empty, expansao: image.empty)

  // tique só avança na partida em si
  check.eq(tique(Abertura(g, img)), Abertura(g, img))
  check.eq(tique(Resultado(g, img, [])), Resultado(g, img, []))

  let p = nova_partida()
  check.eq(tique(EmPartida(g, img, p)), avanca(g, img, p))
}

/// Produz a lista de posições do mapa da *partida* que não tem
/// nem jogador, nem poder
pub fn casas_livres(partida: Partida) -> List(Posicao) {
  let posicoes_poderes = list.map(partida.poderes, fn(poder) { poder.posicao })

  list.filter(todas_as_casas(), fn(pos) {
    !list.contains(posicoes_poderes, pos)
    && !list.any(partida.jogadores, fn(j) { j.posicao == pos })
  })
}

pub fn casas_livres_examples() {
  let p = nova_partida()
  let livre = Posicao(5, 5)

  // Apenas casas com os jogadores
  check.eq(list.length(casas_livres(p)), tamanho * tamanho - 2)

  // Posição do jogador não é livre
  check.eq(list.contains(casas_livres(p), cria_jogador(1).posicao), False)

  // Casa livre
  check.eq(list.contains(casas_livres(p), livre), True)

  let p = Partida(..p, poderes: [PoderNoMapa(Velocidade, livre)])

  // Casa com poder fica não livre
  check.eq(list.contains(casas_livres(p), livre), False)
}

pub fn sorteia_tipo(gerador: Generator) -> #(TipoPoder, Generator) {
  let tipos = [Velocidade, Expansao]

  case random.pick(gerador, tipos) {
    #(Ok(tipo), novo_gerador) -> #(tipo, novo_gerador)
    #(Error(_), novo_gerador) -> #(Velocidade, novo_gerador)
  }
}

pub fn sorteia_tipo_examples() {
  let g =
    random.mock([random.pick_returns([Velocidade, Expansao], Ok(Velocidade))])
  check.eq(sorteia_tipo(g), #(Velocidade, random.mock([])))
  let g =
    random.mock([random.pick_returns([Velocidade, Expansao], Ok(Expansao))])
  check.eq(sorteia_tipo(g), #(Expansao, random.mock([])))
}

/// Adiciona os poderes na *partida*. Se não há casa livre, os poderes
/// não mudam. Devolve os poderes e o novo gerador.
pub fn sorteia_poder(
  gerador: Generator,
  partida: Partida,
) -> #(List(PoderNoMapa), Generator) {
  case random.pick(gerador, casas_livres(partida)) {
    #(Ok(casa), gerador) -> {
      let #(tipo, gerador) = sorteia_tipo(gerador)
      let poder = PoderNoMapa(tipo, casa)

      #([poder, ..partida.poderes], gerador)
    }

    #(Error(_), gerador) -> #(partida.poderes, gerador)
  }
}

pub fn sorteia_poder_examples() {
  let p = nova_partida()
  let pos = Posicao(5, 5)
  let g =
    random.mock([
      random.pick_returns(casas_livres(p), Ok(pos)),
      random.pick_returns([Velocidade, Expansao], Ok(Expansao)),
    ])
  check.eq(sorteia_poder(g, p), #([PoderNoMapa(Expansao, pos)], random.mock([])))
  let p =
    Partida(
      ..p,
      poderes: list.map(todas_as_casas(), fn(pos) { PoderNoMapa(Expansao, pos) }),
    )
  let #(poderes, _) = sorteia_poder(random.new(0), p)
  check.eq(poderes, p.poderes)
}

/// Avança um tique da partida e mostra o resultado
/// quando a duração é atingida.
pub fn avanca(gerador: Generator, imagens: ImagensPoderes, partida: Partida) {
  let tiques = partida.tiques + 1

  case tiques >= duracao {
    True -> Resultado(gerador, imagens, partida.placares)
    False -> {
      let jogadores =
        list.map(partida.jogadores, fn(j) {
          case j.reaparecimento > 0 {
            True -> Jogador(..j, reaparecimento: j.reaparecimento - 1)
            False -> j
          }
        })

      let atualizada = Partida(..partida, tiques: tiques, jogadores: jogadores)
      let movimentada =
        list.fold(jogadores, atualizada, fn(acumulado, jogador) {
          // Converte a velocidade em casas por segundo para tiques por movimento.
          let intervalo =
            int.max(
              1,
              float.round(
                int.to_float(tiques_por_segundo) /. jogador.velocidade,
              ),
            )

          case tiques % intervalo == 0 {
            True -> move(acumulado, jogador.id, jogador.direcao)
            False -> acumulado
          }
        })

        let jogadores =
          list.map(movimentada.jogadores, fn(jogador) {
            case jogador.velocidade_extra {
              1 ->
                Jogador(
                  ..jogador,
                  velocidade_extra: 0,
                  velocidade: velocidade_cobra,
                )

              tempo if tempo > 1 ->
                Jogador(..jogador, velocidade_extra: tempo - 1)

              _ -> jogador
            }
          })

      let movimentada = Partida(..movimentada, jogadores: jogadores)

      case movimentada.proximo_poder <= 1 {
        True -> {
          let #(poderes, novo_gerador) = sorteia_poder(gerador, movimentada)

          let atualizada =
            Partida(..movimentada, poderes: poderes, proximo_poder: delay_poder)

          EmPartida(novo_gerador, imagens, atualizada)
        }

        False -> {
          let atualizada =
            Partida(..movimentada, proximo_poder: movimentada.proximo_poder - 1)

          EmPartida(gerador, imagens, atualizada)
        }
      }
    }
  }
}

pub fn avanca_examples() {
  let g = random.new(0)
  let img = ImagensPoderes(velocidade: image.empty, expansao: image.empty)
  let p = nova_partida()

  // Mostra o resultado quando acabar
  check.eq(
    avanca(g, img, Partida(..p, tiques: duracao - 1)),
    Resultado(g, img, p.placares),
  )

  // Atualiza o delay do poder
  check.eq(
    avanca(g, img, p),
    EmPartida(g, img, Partida(..p, tiques: 1, proximo_poder: delay_poder - 1)),
  )

  let p = Partida(..nova_partida(), tiques: 4)
  let j1 = Jogador(..cria_jogador(1), posicao: Posicao(tamanho - 3, 1))
  let j2 = Jogador(..cria_jogador(2), posicao: Posicao(2, tamanho - 2))

  // Jogadores se movem
  check.eq(
    avanca(g, img, p),
    EmPartida(
      g,
      img,
      Partida(
        ..p,
        tiques: 5,
        proximo_poder: delay_poder - 1,
        jogadores: [j1, j2],
      ),
    ),
  )
}

/// Recalcula os placares da *partida* contando as casas
/// de cada jogador. Mantém a ordem dos jogadores e
/// preserva os demais campos da partida.
pub fn atualizar_placares(partida: Partida) -> Partida {
  let placares =
    list.map(partida.jogadores, fn(jogador) {
      let quantidade = conta_casas(partida, jogador)
      Placar(jogador.id, quantidade)
    })

  Partida(..partida, placares: placares)
}

pub fn atualizar_placares_examples() {
  let p = nova_partida()
  check.eq(atualizar_placares(p).placares, [Placar(1, 9), Placar(2, 9)])
  check.eq(atualizar_placares(Partida(..p, mapa: [])).placares, [
    Placar(1, 0),
    Placar(2, 0),
  ])
  check.eq(atualizar_placares(Partida(..p, jogadores: [])).placares, [])
}

/// Conta as casas do mapa da *partida* que pertencem ao
/// *jogador*. Devolve zero se ele não possuir nenhuma casa.
pub fn conta_casas(partida: Partida, jogador: Jogador) -> Int {
  list.count(partida.mapa, fn(casa) { casa.dono == Some(jogador.id) })
}

pub fn conta_casas_examples() {
  let partida = nova_partida()

  // Cada jogador começa com nove casas.
  check.eq(conta_casas(partida, cria_jogador(1)), 9)
  check.eq(conta_casas(partida, cria_jogador(2)), 9)

  // Casas neutras e de outros jogadores não são contadas.
  let pequena =
    Partida(..partida, mapa: [
      Casa(Posicao(0, 0), Some(1)),
      Casa(Posicao(0, 1), None),
      Casa(Posicao(0, 2), Some(2)),
      Casa(Posicao(0, 3), Some(1)),
    ])

  check.eq(conta_casas(pequena, cria_jogador(1)), 2)
  check.eq(conta_casas(pequena, cria_jogador(2)), 1)

  // Nenhuma casa pertence ao jogador.
  let neutra = Partida(..partida, mapa: cria_mapa())
  check.eq(conta_casas(neutra, cria_jogador(1)), 0)
}

// ----------------------------------------------------------------------
// Posições e movimentação
// ----------------------------------------------------------------------

/// Verifica se uma posição está dentro dos limites do mapa.
pub fn dentro_do_mapa(pos: Posicao) -> Bool {
  pos.lin >= 0 && pos.lin < tamanho && pos.col >= 0 && pos.col < tamanho
}

pub fn dentro_do_mapa_examples() {
  check.eq(dentro_do_mapa(Posicao(0, 0)), True)
  check.eq(dentro_do_mapa(Posicao(19, 19)), True)
  check.eq(dentro_do_mapa(Posicao(-1, 5)), False)
  check.eq(dentro_do_mapa(Posicao(20, 5)), False)
  check.eq(dentro_do_mapa(Posicao(5, -1)), False)
}

/// Calcula o destino, bloqueando as bordas, a base adversária e
/// um adversário ativo. None indica que ele está fora de jogo.
pub fn desloca(
  pos: Posicao,
  dir: Direcao,
  base_adversario: List(Posicao),
  adversario_pos: Option(Posicao),
) -> Posicao {
  let destino = case dir {
    Cima -> Posicao(pos.lin - 1, pos.col)
    Baixo -> Posicao(pos.lin + 1, pos.col)
    Esquerda -> Posicao(pos.lin, pos.col - 1)
    Direita -> Posicao(pos.lin, pos.col + 1)
  }

  case
    dentro_do_mapa(destino),
    list.contains(base_adversario, destino),
    Some(destino) == adversario_pos
  {
    True, False, False -> destino
    _, _, _ -> pos
  }
}

pub fn desloca_examples() {
  let pos = Posicao(5, 5)
  check.eq(desloca(pos, Cima, [], None), Posicao(4, 5))
  check.eq(desloca(pos, Direita, [], None), Posicao(5, 6))

  // Não sai da borda
  check.eq(desloca(Posicao(0, 0), Esquerda, [], None), Posicao(0, 0))

  // Não pode entrar na base adversária
  check.eq(desloca(pos, Direita, [Posicao(5, 6)], None), pos)

  // Não deixa entrar na mesma casa que o adversário
  check.eq(desloca(pos, Direita, [], Some(Posicao(5, 6))), pos)
}

/// Devolve o dono da casa na posição pos.
/// Devolve None se a casa for neutra ou não estiver no mapa.
pub fn dono_da_casa(mapa: List(Casa), pos: Posicao) -> Option(Int) {
  case list.find(mapa, fn(casa) { casa.posicao == pos }) {
    Ok(casa) -> casa.dono
    Error(_) -> None
  }
}

pub fn dono_da_casa_examples() {
  let partida = nova_partida()

  check.eq(dono_da_casa(partida.mapa, Posicao(17, 2)), Some(1))
  check.eq(dono_da_casa(partida.mapa, Posicao(2, 17)), Some(2))
  check.eq(dono_da_casa(partida.mapa, Posicao(10, 10)), None)
}

/// Move o jogador na direção escolhida. Se ele estiver esperando
/// para reaparecer, mantém a partida sem alterações.
pub fn move(partida: Partida, jogador_id: Int, direcao: Direcao) -> Partida {
  let adversario = list.find(partida.jogadores, fn(j) { j.id != jogador_id })

  case busca_jogador(partida.jogadores, jogador_id), adversario {
    Ok(jogador), Ok(adversario) if jogador.reaparecimento == 0 ->
      mover_jogador(partida, jogador, direcao, adversario)
    _, _ -> partida
  }
}

pub fn move_examples() {
  let partida = nova_partida()

  let movida = move(partida, 1, Cima)

  check.eq(list.map(movida.jogadores, fn(j) { j.posicao }), [
    Posicao(17, 1),
    Posicao(1, 18),
  ])

  check.eq(move(partida, 3, Cima), partida)
}


/// Reinicia o jogador após ser eliminado. Posiciona-o no centro da base,
/// restaura a direção inicial, limpa o rastro e os poderes e restaura a
/// velocidade padrão. Preserva o território conquistado e inicia
/// a espera de dois segundos para reaparecer.
pub fn reinicia_jogador(jogador: Jogador) -> Jogador {
  let jogador_inicial = cria_jogador(jogador.id)

  Jogador(..jogador_inicial, reaparecimento: 2 * tiques_por_segundo)
}

pub fn reinicia_jogador_examples() {
  let j =
    Jogador(
      ..cria_jogador(1),
      posicao: Posicao(5, 5),
      rastro: [Posicao(5, 4)],
      poderes_guardados: [Velocidade],
      velocidade_extra: 10,
      velocidade: velocidade_boost,
    )
  check.eq(
    reinicia_jogador(j),
    Jogador(..cria_jogador(1), reaparecimento: 2 * tiques_por_segundo),
  )
  check.eq(
    reinicia_jogador(cria_jogador(2)),
    Jogador(..cria_jogador(2), reaparecimento: 2 * tiques_por_segundo),
  )
}


/// Atualiza a posição e o rastro do jogador.
/// Se ele voltar ao próprio território com um rastro,
/// transforma o caminho em território e limpa o rastro.
pub fn mover_jogador(
  partida: Partida,
  jogador: Jogador,
  direcao: Direcao,
  adversario: Jogador,
) -> Partida {
  let adversario_pos = case adversario.reaparecimento == 0 {
    True -> Some(adversario.posicao)
    False -> None
  }

  let nova_pos =
    desloca(
      jogador.posicao,
      direcao,
      adversario.base,
      adversario_pos,
    )

  let moveu = nova_pos != jogador.posicao
  let cortou_rastro = moveu && list.contains(jogador.rastro, nova_pos)
  let cortou_rastro_adversario =
    moveu && list.contains(adversario.rastro, nova_pos)
  let voltou_area = dono_da_casa(partida.mapa, nova_pos) == Some(jogador.id)
  let fechou_rastro = moveu && voltou_area && jogador.rastro != []

  let poder = case moveu {
    True -> list.find(partida.poderes, fn(p) { p.posicao == nova_pos })
    False -> Error(Nil)
  }

  let jogador_com_poder = case poder {
    Ok(p) -> {
      Jogador(..jogador, poderes_guardados: [
        p.tipo,
        ..jogador.poderes_guardados
      ])
    }
    Error(_) -> jogador
  }

  let poderes = case poder {
    Ok(p) ->
      list.filter(partida.poderes, fn(outro) { outro.posicao != p.posicao })

    Error(_) -> partida.poderes
  }

  let mapa = case fechou_rastro {
    True -> fechar_rastro(partida, jogador)
    False -> partida.mapa
  }
  let rastro = case fechou_rastro {
    True -> []
    False -> atualizar_rastro(partida, jogador, nova_pos)
  }

  let jogador_movido = case cortou_rastro {
    True -> reinicia_jogador(jogador_com_poder)
    False -> Jogador(..jogador_com_poder, posicao: nova_pos, rastro: rastro)
  }
  let novo_adversario = case cortou_rastro_adversario {
    True -> reinicia_jogador(adversario)
    False -> adversario
  }

  let jogadores =
    atualiza_jogador(partida.jogadores, jogador.id, fn(_) {
      jogador_movido
    })
    |> atualiza_jogador(adversario.id, fn(_) { novo_adversario })

  let atualizada =
    Partida(..partida, mapa: mapa, jogadores: jogadores, poderes: poderes)

  case fechou_rastro {
    True -> atualizar_placares(atualizada)
    False -> atualizada
  }
}

pub fn mover_jogador_examples() {
  let p = nova_partida()
  let j = cria_jogador(1)
  let outro = cria_jogador(2)

  // Move uma casa para cima, ainda dentro da própria base.
  let movida = mover_jogador(p, j, Cima, outro)

  check.eq(
    busca_jogador(movida.jogadores, 1),
    Ok(Jogador(..j, posicao: Posicao(tamanho - 3, 1))),
  )

  // Entrar no próprio rastro elimina o jogador.
  let j = Jogador(..j, posicao: Posicao(5, 5), rastro: [Posicao(5, 6)])
  let p = Partida(..p, jogadores: [j, outro])
  let eliminada = mover_jogador(p, j, Direita, outro)

  check.eq(
    busca_jogador(eliminada.jogadores, 1),
    Ok(reinicia_jogador(j)),
  )

  // Cortar o rastro adversário elimina o dono daquele rastro.
  let j = Jogador(..cria_jogador(1), posicao: Posicao(5, 5))
  let outro = Jogador(..outro, rastro: [Posicao(5, 6)])
  let p = Partida(..nova_partida(), jogadores: [j, outro])
  let cortada = mover_jogador(p, j, Direita, outro)

  check.eq(
    busca_jogador(cortada.jogadores, 2),
    Ok(reinicia_jogador(outro)),
  )

  // Quando entra na casa de um poder, guarda ele e o remove do mapa.
  let outro = cria_jogador(2)
  let p =
    Partida(
      ..nova_partida(),
      jogadores: [j, outro],
      poderes: [PoderNoMapa(Velocidade, Posicao(5, 6))],
    )
  let coletada = mover_jogador(p, j, Direita, outro)

  check.eq(
    busca_jogador(coletada.jogadores, 1),
    Ok(Jogador(
      ..j,
      posicao: Posicao(5, 6),
      rastro: [Posicao(5, 6)],
      poderes_guardados: [Velocidade],
    )),
  )
  check.eq(coletada.poderes, [])
}

/// Conquista o rastro e as casas cercadas ao voltar
/// ao território do jogador.
pub fn fechar_rastro(partida: Partida, jogador: Jogador) -> List(Casa) {
  criar_mascara(partida, jogador)
  |> casas_exteriores
  |> pintar_mapa(partida.mapa, _, jogador.id)
}

pub fn fechar_rastro_examples() {
  let jogador = Jogador(..cria_jogador(1), rastro: [Posicao(0, 1)])

  let partida =
    Partida(..nova_partida(), mapa: [
      Casa(Posicao(0, 0), Some(1)),
      Casa(Posicao(0, 1), None),
      Casa(Posicao(0, 2), None),
    ])

  check.eq(fechar_rastro(partida, jogador), [
    Casa(Posicao(0, 0), Some(1)),
    Casa(Posicao(0, 1), Some(1)),
    Casa(Posicao(0, 2), None),
  ])
}

/// Mantém o rastro dentro do próprio território ou
/// adiciona a posição quando o jogador está fora dele.
pub fn atualizar_rastro(
  partida: Partida,
  jogador: Jogador,
  pos: Posicao,
) -> List(Posicao) {
  case dono_da_casa(partida.mapa, pos) {
    Some(dono) if dono == jogador.id -> jogador.rastro
    _ -> adicionar_rastro(pos, jogador.rastro)
  }
}

pub fn atualizar_rastro_examples() {
  let p = nova_partida()
  let j = cria_jogador(1)

  // Jogador está dentro da base ainda
  check.eq(atualizar_rastro(p, j, j.posicao), [])

  // Jogador fora da base
  check.eq(atualizar_rastro(p, j, Posicao(5, 5)), [Posicao(5, 5)])

  let j = Jogador(..j, rastro: [Posicao(5, 5)])

  // Só atualiza se já não é dono
  check.eq(atualizar_rastro(p, j, Posicao(5, 5)), j.rastro)
  check.eq(atualizar_rastro(p, j, Posicao(5, 6)), [Posicao(5, 6), Posicao(5, 5)])
}

/// Adiciona a posição *pos* na lista *rastro*. Caso a
/// posição já esteja na lista, não muda o rastro
pub fn adicionar_rastro(pos: Posicao, rastro: List(Posicao)) -> List(Posicao) {
  case list.contains(rastro, pos) {
    True -> rastro
    False -> [pos, ..rastro]
  }
}

pub fn adicionar_rastro_examples() {
  let a = Posicao(1, 1)
  let b = Posicao(1, 2)
  check.eq(adicionar_rastro(a, []), [a])
  check.eq(adicionar_rastro(a, [a]), [a])
  check.eq(adicionar_rastro(b, [a]), [b, a])
  check.eq(adicionar_rastro(a, [b, a]), [b, a])
  check.eq(adicionar_rastro(b, [b, a]), [b, a])
}

// ----------------------------------------------------------------------
// Flood Fill
// ----------------------------------------------------------------------

/// Estado de uma casa na máscara
pub type EstadoCasa {
  NaoExplorada
  TerritorioOuRastro
  Exterior
}

/// Cria a máscara na mesma ordem das casas do mapa.
/// O território e o rastro do jogador formam a barreira.
/// As outras casas começam como não exploradas.
pub fn criar_mascara(partida: Partida, jogador: Jogador) -> List(EstadoCasa) {
  list.map(partida.mapa, fn(casa) {
    case
      casa.dono == Some(jogador.id)
      || list.contains(jogador.rastro, casa.posicao)
    {
      True -> TerritorioOuRastro
      False -> NaoExplorada
    }
  })
}

pub fn criar_mascara_examples() {
  let jogador = Jogador(..cria_jogador(1), rastro: [Posicao(0, 1)])

  let partida =
    Partida(..nova_partida(), mapa: [
      Casa(Posicao(0, 0), Some(1)),
      Casa(Posicao(0, 1), None),
      Casa(Posicao(0, 2), Some(2)),
    ])

  check.eq(criar_mascara(partida, jogador), [
    TerritorioOuRastro,
    TerritorioOuRastro,
    NaoExplorada,
  ])
}

/// Retorna True se a posição não pode ser explorada,
/// ou seja, se está fora do mapa, é território ou
/// rastro, ou se já foi explorada
pub fn marcada(mascara: List(EstadoCasa), pos: Posicao) -> Bool {
  case dentro_do_mapa(pos) {
    False -> True
    True -> {
      let estado_casa =
        consultar_indice(
          mascara,
          pos.lin * tamanho + pos.col,
          TerritorioOuRastro,
        )

      estado_casa != NaoExplorada
    }
  }
}

pub fn marcada_examples() {
  let mascara = [
    NaoExplorada,
    TerritorioOuRastro,
    Exterior,
  ]

  check.eq(marcada(mascara, Posicao(0, 0)), False)
  check.eq(marcada(mascara, Posicao(0, 1)), True)
  check.eq(marcada(mascara, Posicao(0, 2)), True)
  check.eq(marcada(mascara, Posicao(-1, 0)), True)

  check.eq(marcada(mascara, Posicao(0, tamanho)), True)
}

/// Devolve o elemento no índice *indice*. Caso
/// o índice não existir, devolve *default*
pub fn consultar_indice(lista: List(a), indice: Int, default: a) -> a {
  case lista, indice {
    [primeiro, ..], 0 -> primeiro
    [_, ..resto], n if n > 0 -> consultar_indice(resto, n - 1, default)
    _, _ -> default
  }
}

pub fn consultar_indice_examples() {
  check.eq(consultar_indice([10, 20, 30], 1, 0), 20)
  check.eq(consultar_indice([10], 3, 0), 0)
  check.eq(consultar_indice([], 0, 0), 0)

  // Default
  check.eq(consultar_indice([10], -1, 0), 0)
}

/// Devolve as posições não exploradas nas quatro bordas.
pub fn bordas_livres(mascara: List(EstadoCasa)) -> List(Posicao) {
  list.filter(todas_as_casas(), fn(pos) {
    let borda =
      pos.lin == 0
      || pos.lin == tamanho - 1
      || pos.col == 0
      || pos.col == tamanho - 1

    borda && !marcada(mascara, pos)
  })
}

pub fn bordas_livres_examples() {
  check.eq(
    bordas_livres([
      NaoExplorada,
      TerritorioOuRastro,
      NaoExplorada,
    ]),
    [Posicao(0, 0), Posicao(0, 2)],
  )

  // Só marca se estiver livre
  check.eq(bordas_livres([TerritorioOuRastro]), [])
}

/// Define o tipo trecho que contém a linha que estamos
/// analisando, o inicio do trecho e o fim dele
pub type Trecho {
  Trecho(linha: Int, inicio: Int, fim: Int)
}

/// Encontra o limite do trecho não explorado na direção indicada.
/// A posição inicial deve ser não explorada.
pub fn limite_trecho(
  mascara: List(EstadoCasa),
  pos: Posicao,
  direcao: Direcao,
) -> Int {
  let proxima = case direcao {
    Direita -> Posicao(pos.lin, pos.col + 1)
    Esquerda -> Posicao(pos.lin, pos.col - 1)
    _ -> pos
  }

  case proxima == pos || marcada(mascara, proxima) {
    True -> pos.col
    False -> limite_trecho(mascara, proxima, direcao)
  }
}

pub fn limite_trecho_examples() {
  let mascara = [
    TerritorioOuRastro,
    NaoExplorada,
    NaoExplorada,
    NaoExplorada,
    TerritorioOuRastro,
  ]

  // Limite para os dois lados
  check.eq(limite_trecho(mascara, Posicao(0, 2), Esquerda), 1)
  check.eq(limite_trecho(mascara, Posicao(0, 2), Direita), 3)

  // Para na borda esquerda
  check.eq(limite_trecho([NaoExplorada], Posicao(0, 0), Esquerda), 0)
}

/// Encontra o trecho não explorado que contém pos
pub fn encontrar_trecho(mascara: List(EstadoCasa), pos: Posicao) -> Trecho {
  Trecho(
    linha: pos.lin,
    inicio: limite_trecho(mascara, pos, Esquerda),
    fim: limite_trecho(mascara, pos, Direita),
  )
}

pub fn encontrar_trecho_examples() {
  let mascara = [
    TerritorioOuRastro,
    NaoExplorada,
    NaoExplorada,
    TerritorioOuRastro,
  ]

  check.eq(
    encontrar_trecho(mascara, Posicao(0, 1)),
    Trecho(linha: 0, inicio: 1, fim: 2),
  )
}

/// Marca todas as casas do trecho como exteriores.
pub fn marcar_trecho(
  mascara: List(EstadoCasa),
  trecho: Trecho,
) -> List(EstadoCasa) {
  let inicio = trecho.linha * tamanho + trecho.inicio
  let fim = trecho.linha * tamanho + trecho.fim

  marcar_intervalo(mascara, 0, inicio, fim)
}

pub fn marcar_trecho_examples() {
  // Marca do inicio até o fim
  check.eq(
    marcar_trecho(
      [NaoExplorada, NaoExplorada, NaoExplorada],
      Trecho(linha: 0, inicio: 1, fim: 2),
    ),
    [NaoExplorada, Exterior, Exterior],
  )
}

/// Percorre a máscara a partir de indice, colocando True
/// entre inicio e fim.
pub fn marcar_intervalo(
  mascara: List(EstadoCasa),
  indice: Int,
  inicio: Int,
  fim: Int,
) -> List(EstadoCasa) {
  case mascara {
    _ if indice > fim -> mascara
    [] -> []
    [primeiro, ..resto] -> {
      let novo_valor = case indice >= inicio {
        True -> Exterior
        False -> primeiro
      }

      [novo_valor, ..marcar_intervalo(resto, indice + 1, inicio, fim)]
    }
  }
}

pub fn marcar_intervalo_examples() {
  // Marca só no intervalo requerido
  check.eq(
    marcar_intervalo(
      [
        TerritorioOuRastro,
        NaoExplorada,
        NaoExplorada,
        NaoExplorada,
      ],
      0,
      1,
      2,
    ),
    [
      TerritorioOuRastro,
      Exterior,
      Exterior,
      NaoExplorada,
    ],
  )

  // Sem casa para marcar
  check.eq(marcar_intervalo([], 0, 0, 1), [])
}
/// Adiciona às pendentes o começo de cada grupo não explorado
/// na linha, entre as colunas inicial e final do trecho.
pub fn conexoes_linha(
  mascara: List(EstadoCasa),
  trecho: Trecho,
  linha: Int,
  pendentes: List(Posicao),
) -> List(Posicao) {
  procurar_conexoes(
    mascara,
    linha,
    trecho.inicio,
    trecho.fim,
    True,
    pendentes,
  )
}

pub fn conexoes_linha_examples() {
  let mascara = [
    NaoExplorada,
    NaoExplorada,
    TerritorioOuRastro,
    NaoExplorada,
  ]

  let trecho = Trecho(linha: 1, inicio: 0, fim: 3)

  // Uma posição por sequencia
  check.eq(conexoes_linha(mascara, trecho, 0, []), [
    Posicao(0, 3),
    Posicao(0, 0),
  ])

  // Fora do mapa
  check.eq(conexoes_linha(mascara, trecho, -1, []), [])

  // Se já existe uma posição pendente
  check.eq(conexoes_linha(mascara, trecho, 0, [Posicao(5, 5)]), [
    Posicao(0, 3),
    Posicao(0, 0),
    Posicao(5, 5),
  ])
}

/// Percorre a linha da coluna atual até fim, guardando em
/// pendentes a primeira posição de cada grupo não explorado.
fn procurar_conexoes(
  mascara: List(EstadoCasa),
  linha: Int,
  coluna: Int,
  fim: Int,
  marcar_inicio: Bool,
  pendentes: List(Posicao),
) -> List(Posicao) {
  case coluna > fim {
    True -> pendentes

    False -> {
      let pos = Posicao(linha, coluna)
      let bloqueada = marcada(mascara, pos)

      let pendentes = case marcar_inicio && !bloqueada {
        True -> [pos, ..pendentes]
        False -> pendentes
      }

      procurar_conexoes(mascara, linha, coluna + 1, fim, bloqueada, pendentes)
    }
  }
}

pub fn procurar_conexoes_examples() {
  check.eq(procurar_conexoes([NaoExplorada, NaoExplorada], 0, 0, 1, True, []), [
    Posicao(0, 0),
  ])

  // Já está em uma seq marcada
  check.eq(
    procurar_conexoes([NaoExplorada, NaoExplorada], 0, 0, 1, False, []),
    [],
  )
}

/// Explora as posições pendentes, preenchendo um trecho
/// por vez como Exterior. Para cada trecho, procura passagens
/// acima e abaixo e as adiciona às pendentes.
pub fn scanline_fill(
  mascara: List(EstadoCasa),
  pendentes: List(Posicao),
) -> List(EstadoCasa) {
  case pendentes {
    [] -> mascara

    [pos, ..resto] -> {
      case marcada(mascara, pos) {
        True -> scanline_fill(mascara, resto)

        False -> {
          let trecho = encontrar_trecho(mascara, pos)
          let mascara = marcar_trecho(mascara, trecho)

          let pendentes =
            conexoes_linha(mascara, trecho, trecho.linha - 1, resto)

          let pendentes =
            conexoes_linha(mascara, trecho, trecho.linha + 1, pendentes)

          scanline_fill(mascara, pendentes)
        }
      }
    }
  }
}

pub fn scanline_fill_examples() {
  let mascara = [
    NaoExplorada,
    NaoExplorada,
    TerritorioOuRastro,
    NaoExplorada,
  ]

  // A barreira impede chegar ao segundo grupo.
  check.eq(scanline_fill(mascara, [Posicao(0, 0)]), [
    Exterior,
    Exterior,
    TerritorioOuRastro,
    NaoExplorada,
  ])

  check.eq(scanline_fill(mascara, []), mascara)

  // Uma posição repetida não altera o resultado.
  check.eq(
    scanline_fill([NaoExplorada], [
      Posicao(0, 0),
      Posicao(0, 0),
    ]),
    [Exterior],
  )
}

/// Marca as casas alcançáveis pelas quatro bordas,
/// sem atravessar o território nem o rastro do jogador.
pub fn casas_exteriores(mascara: List(EstadoCasa)) -> List(EstadoCasa) {
  bordas_livres(mascara)
  |> scanline_fill(mascara, _)
}

pub fn casas_exteriores_examples() {
  // A casa livre está na borda superior, então é exterior,
  // mesmo com território dos dois lados.
  check.eq(
    casas_exteriores([
      TerritorioOuRastro,
      NaoExplorada,
      TerritorioOuRastro,
    ]),
    [
      TerritorioOuRastro,
      Exterior,
      TerritorioOuRastro,
    ],
  )
}

/// Não muda o dono das casas exteriores e conquista o resto.
/// Após o fill, NaoExplorada representa uma casa cercada.
pub fn pintar_mapa(
  casas: List(Casa),
  mascara: List(EstadoCasa),
  jogador_id: Int,
) -> List(Casa) {
  case casas, mascara {
    [], _ -> []
    [casa, ..resto_casas], [estado, ..resto_mascara] -> {
      let nova_casa = case estado {
        Exterior -> casa
        _ -> Casa(..casa, dono: Some(jogador_id))
      }
      [nova_casa, ..pintar_mapa(resto_casas, resto_mascara, jogador_id)]
    }
    _, _ -> casas
  }
}

pub fn pintar_mapa_examples() {
  let casas = [
    Casa(Posicao(0, 0), Some(2)),
    Casa(Posicao(0, 1), None),
    Casa(Posicao(0, 2), Some(2)),
  ]

  let mascara = [
    Exterior,
    TerritorioOuRastro,
    NaoExplorada,
  ]

  check.eq(pintar_mapa(casas, mascara, 1), [
    // Exterior fica com o dono.
    Casa(Posicao(0, 0), Some(2)),
    // Rastro continua com o jogador.
    Casa(Posicao(0, 1), Some(1)),
    // Casa cercada é conquistada.
    Casa(Posicao(0, 2), Some(1)),
  ])
}


// ----------------------------------------------------------------------
// Poderes
// ----------------------------------------------------------------------
pub fn remover_poder(
  poderes: List(TipoPoder),
  tipo: TipoPoder,
) -> List(TipoPoder) {
  case poderes {
    [] -> []
    [primeiro, ..resto] if primeiro == tipo -> resto
    [primeiro, ..resto] -> [primeiro, ..remover_poder(resto, tipo)]
  }
}

pub fn remover_poder_examples() {
  check.eq(remover_poder([], Velocidade), [])
  check.eq(remover_poder([Velocidade], Velocidade), [])
  check.eq(remover_poder([Expansao], Velocidade), [Expansao])
  check.eq(remover_poder([Expansao, Velocidade], Velocidade), [Expansao])
  check.eq(remover_poder([Velocidade, Velocidade], Velocidade), [Velocidade])
}

pub fn ativar_expansao(j: Jogador, partida: Partida) -> Partida {
  let base_adversaria =
    case list.find(partida.jogadores, fn(outro) { outro.id != j.id }) {
      Ok(adversario) -> adversario.base
      Error(_) -> []
    }
  let mapa =
    list.map(partida.mapa, fn(casa) {
      let perto =
        casa.posicao.lin >= j.posicao.lin - 1
        && casa.posicao.lin <= j.posicao.lin + 1
        && casa.posicao.col >= j.posicao.col - 1
        && casa.posicao.col <= j.posicao.col + 1

      case perto && !list.contains(base_adversaria, casa.posicao) {
        True -> Casa(..casa, dono: Some(j.id))
        False -> casa
      }
    })

  atualizar_placares(Partida(..partida, mapa: mapa))
}

pub fn ativar_expansao_examples() {
  let j = Jogador(..cria_jogador(1), posicao: Posicao(5, 5))
  let p = Partida(..nova_partida(), mapa: cria_mapa())
  let expandida = ativar_expansao(j, p)

  // Checa que apenas as 9 casas foram conquistadas
  check.eq(conta_casas(expandida, j), 9)
  check.eq(dono_da_casa(expandida.mapa, Posicao(5, 7)), None)

  let j = Jogador(..j, posicao: cria_jogador(2).posicao)

  // A expansão não atinge a base adversária
  check.eq(ativar_expansao(j, nova_partida()).mapa, nova_partida().mapa)
}

/// Ativa o poder se ele estiver guardado no inventário do jogador.
/// Aplica o efeito e consome uma unidade; se o jogador não existir
/// ou não possuir o poder, mantém a partida.
pub fn ativar_poder(
  partida: Partida,
  jogador_id: Int,
  tipo: TipoPoder,
) -> Partida {
  case busca_jogador(partida.jogadores, jogador_id) {
    Error(_) -> partida
    Ok(jogador) -> {
      case list.contains(jogador.poderes_guardados, tipo) {
        False -> partida
        True -> {
          let jogador =
            Jogador(
              ..jogador,
              poderes_guardados: remover_poder(jogador.poderes_guardados, tipo),
            )

          let jogador = case tipo {
            Velocidade ->
              Jogador(
                ..jogador,
                velocidade: velocidade_boost,
                velocidade_extra: boost_tempo,
              )
            Expansao -> jogador
          }

          let atualizada = case tipo {
            Expansao -> ativar_expansao(jogador, partida)
            Velocidade -> partida
          }

          let jogadores =
            atualiza_jogador(atualizada.jogadores, jogador_id, fn(_) {
              jogador
            })

          Partida(..atualizada, jogadores: jogadores)
        }
      }
    }
  }
}

pub fn ativar_poder_examples() {
  let p = nova_partida()

  // Jogador ainda não tem poder ou não existe
  check.eq(ativar_poder(p, 1, Velocidade), p)
  check.eq(ativar_poder(p, 3, Expansao), p)

  let j =
    Jogador(..cria_jogador(1), poderes_guardados: [Velocidade, Velocidade])

  let p = Partida(..p, jogadores: [j, cria_jogador(2)])
  let acelerada = ativar_poder(p, 1, Velocidade)

  // Jogador com boost de velocidade
  check.eq(
    busca_jogador(acelerada.jogadores, 1),
    Ok(
      Jogador(
        ..j,
        poderes_guardados: [Velocidade],
        velocidade: velocidade_boost,
        velocidade_extra: boost_tempo,
      ),
    ),
  )
}

// ----------------------------------------------------------------------
// Desenho
// ----------------------------------------------------------------------

/// Devolve a cor do jogador *numero*.
pub fn cor(numero: Int) -> Color {
  case numero {
    1 -> color.green
    2 -> color.blue
    _ -> color.purple
  }
}

pub fn cor_examples() {
  check.eq(cor(1), color.green)
  check.eq(cor(2), color.blue)
  check.eq(cor(4), color.purple)

  check.eq(cor(0), color.purple)
  check.eq(cor(-1), color.purple)
}

/// Produz a cor de uma casa conforme seu proprietário.
fn cor_casa(dono: Option(Int)) -> Color {
  case dono {
    Some(1) -> color.green
    Some(2) -> color.blue
    _ -> color.white
  }
}

pub fn cor_casa_examples() {
  check.eq(cor_casa(Some(1)), color.green)
  check.eq(cor_casa(Some(2)), color.blue)
  check.eq(cor_casa(None), color.white)
  check.eq(cor_casa(Some(3)), color.white)
}

/// Produz a cor de um rastro conforme seu proprietário.
fn cor_rastro(id: Int) -> Color {
  case id {
    1 -> color.springgreen
    2 -> color.powderblue
    _ -> color.white
  }
}

pub fn cor_rastro_examples() {
  check.eq(cor_rastro(1), color.springgreen)
  check.eq(cor_rastro(2), color.powderblue)
  check.eq(cor_rastro(3), color.white)
  check.eq(cor_rastro(0), color.white)
}

/// Desenha a tela do *estado* para o jogador *numero*.
pub fn tela(estado: Estado, id: Int) -> Image {
  let conteudo = case estado {
    Abertura(_, _) -> tela_abertura(id)
    EmPartida(_, imagens, partida) -> tela_partida(imagens, partida, id)
    Resultado(_, _, jogadores) -> tela_resultado(jogadores, id)
  }
  image.overlay(conteudo, image.rectangle(largura, altura, fill.white))
}

fn desenha_casa(casa: Casa) -> Image {
  image.square(
    lado_casa,
    style.join([
      style.fill(cor_casa(casa.dono)),
      case casa.dono {
        Some(1) -> style.stroke(color.green)
        Some(2) -> style.stroke(color.blue)
        _ -> style.stroke(color.grey)
      },
    ]),
  )
}

pub fn desenha_casa_examples() {
  check.same(
    desenha_casa(Casa(Posicao(0, 0), None)),
    image.square(
      lado_casa,
      style.join([style.fill(color.white), style.stroke(color.grey)]),
    ),
  )
  check.same(
    desenha_casa(Casa(Posicao(0, 0), Some(1))),
    image.square(
      lado_casa,
      style.join([style.fill(color.green), style.stroke(color.green)]),
    ),
  )
}

fn desenha_rastro(id: Int) -> Image {
  image.square(lado_casa, style.fill(cor_rastro(id)))
}

pub fn desenha_rastro_examples() {
  check.same(
    desenha_rastro(1),
    image.square(lado_casa, style.fill(color.springgreen)),
  )
  check.same(
    desenha_rastro(2),
    image.square(lado_casa, style.fill(color.powderblue)),
  )
}

fn desenha_poder(imagens: ImagensPoderes, tipo: TipoPoder) -> Image {
  case tipo {
    Expansao -> imagens.expansao
    Velocidade -> imagens.velocidade
  }
}

/// Coloca uma imagem no centro de uma posição do mapa.
fn coloca_img(img: Image, pos: Posicao, elemento: Image) -> Image {
  image.place_image(
    img,
    pos.col * lado_casa + lado_casa / 2,
    pos.lin * lado_casa + lado_casa / 2,
    elemento,
  )
}

/// Produz a imagem de um jogador.
fn desenha_jogador(j: Jogador) -> Image {
  image.square(
    lado_casa - 8,
    style.join([
      style.fill(cor_casa(Some(j.id))),
      style.stroke(color.black),
    ]),
  )
}

/// Produz a imagem do mapa com suas casas e jogadores.
pub fn grade(partida: Partida, imagens_poderes: ImagensPoderes) -> Image {
  image.rectangle(
    tamanho * lado_casa,
    tamanho * lado_casa,
    style.fill(color.white),
  )
  |> list.fold(partida.mapa, _, fn(cena, casa) {
    coloca_img(cena, casa.posicao, desenha_casa(casa))
  })
  |> list.fold(partida.jogadores, _, fn(cena, j) {
    let quadrado = desenha_rastro(j.id)

    list.fold(j.rastro, cena, fn(imagem, pos) {
      coloca_img(imagem, pos, quadrado)
    })
  })
  |> list.fold(partida.poderes, _, fn(imagem, poder) {
    coloca_img(
      imagem,
      poder.posicao,
      desenha_poder(imagens_poderes, poder.tipo),
    )
  })
  |> list.fold(partida.jogadores, _, fn(cena, j) {
    case j.reaparecimento == 0 {
      True -> coloca_img(cena, j.posicao, desenha_jogador(j))
      False -> cena
    }
  })
}

// ----------------------------------------------------------------------
// Desenho - Telas
// ----------------------------------------------------------------------

/// Mostra a identificação do jogador e como começar.
pub fn tela_abertura(id: Int) -> Image {
  image.above(
    image.text("Disputa de Território", 32, fill.black),
    image.above(
      image.text(
        "Você é o jogador " <> int.to_string(id),
        22,
        style.fill(cor(id)),
      ),
      image.text("Enter para começar. Setas para mover.", 20, fill.black),
    ),
  )
}

/// Mostra o tempo, os placares e o tabuleiro.
pub fn tela_partida(
  imagens_poderes: ImagensPoderes,
  partida: Partida,
  id: Int,
) -> Image {
  let jogador = busca_jogador(partida.jogadores, id)

  let segundos =
    { duracao - partida.tiques + tiques_por_segundo - 1 } / tiques_por_segundo

  let poderes = case jogador {
    Ok(j) -> {
      case j.poderes_guardados {
        [] -> image.empty

        _ -> {
          let quantidade = list.length(j.poderes_guardados)

          let texto =
            image.text(
              "Poderes (" <> int.to_string(quantidade) <> "): ",
              18,
              fill.black,
            )

          let icones =
            list.fold(j.poderes_guardados, image.empty, fn(imagem, tipo) {
              image.beside(imagem, desenha_poder(imagens_poderes, tipo))
            })

          image.beside(texto, icones)
        }
      }
    }

    Error(_) -> image.empty
  }

  let espaco_poderes =
    image.overlay(poderes, image.rectangle(largura, 36, fill.white))

  let placar =
    list.fold(partida.placares, image.empty, fn(cena, p) {
      let nome = case p.jogador == id {
        True -> "Você"
        False -> "Adversário"
      }

      image.beside(
        cena,
        image.text(
          nome <> ": " <> int.to_string(p.casas) <> "   ",
          20,
          style.fill(cor(p.jogador)),
        ),
      )
    })

  let tabuleiro = grade(partida, imagens_poderes)

  let tabuleiro = case jogador {
    Ok(j) if j.reaparecimento > 0 -> {
      let segundos_restantes =
        { j.reaparecimento + tiques_por_segundo - 1 } / tiques_por_segundo

      let aviso =
        image.overlay(
          image.text(
            "Reaparecendo em " <> int.to_string(segundos_restantes) <> " s",
            20,
            fill.black,
          ),
          image.rectangle(260, 48, fill.white),
        )

      image.overlay(aviso, tabuleiro)
    }

    _ -> tabuleiro
  }

  let cabecalho =
    image.above(
      image.above(
        image.text("Tempo: " <> int.to_string(segundos) <> " s", 24, fill.black),
        placar,
      ),
      espaco_poderes,
    )

  image.above(cabecalho, tabuleiro)
}

/// Devolve a mensagem do resultado para o jogador indicado.
pub fn mensagem_resultado(placares: List(Placar), id: Int) -> String {
  let seu_placar = list.find(placares, fn(p) { p.jogador == id })
  let adversario = list.find(placares, fn(p) { p.jogador != id })

  case seu_placar, adversario {
    Ok(seu), Ok(outro) -> {
      case seu.casas > outro.casas, seu.casas == outro.casas {
        True, _ -> "Você venceu!"
        _, True -> "Empate!"
        _, _ -> "Derrota!"
      }
    }
    _, _ -> "Fim da partida"
  }
}

pub fn mensagem_resultado_examples() {
  let placares = [Placar(1, 20), Placar(2, 10)]
  check.eq(mensagem_resultado(placares, 1), "Você venceu!")
  check.eq(mensagem_resultado(placares, 2), "Derrota!")
  check.eq(mensagem_resultado([Placar(1, 10), Placar(2, 10)], 1), "Empate!")
  check.eq(mensagem_resultado([], 1), "Fim da partida")
  check.eq(mensagem_resultado(placares, 3), "Fim da partida")
}

/// Mostra o resultado e os placares finais e permite voltar à abertura.
pub fn tela_resultado(placares: List(Placar), id: Int) -> Image {
  let placar =
    list.fold(placares, image.empty, fn(cena, p) {
      let nome = case p.jogador == id {
        True -> "Você"
        False -> "Adversário"
      }

      image.above(
        cena,
        image.text(
          nome <> ": " <> int.to_string(p.casas) <> " casas",
          24,
          style.fill(cor(p.jogador)),
        ),
      )
    })

  image.above(
    image.text(mensagem_resultado(placares, id), 32, fill.black),
    image.above(
      placar,
      image.text("Pressione Enter para voltar ao menu", 20, fill.black),
    ),
  )
}
