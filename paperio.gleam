// Disputa de Território
//
// Jogo multijogador inspirado no Paper.io para o Trabalho 01.
//
// Autores: Bruno Rafael Comin Scheffel e José Luis Peres de Sousa
//
// Regras
//
// - Dois jogadores. Cada jogador começa com uma pequena base própria
//   em um lado do tabuleiro.
// - Ao sair do próprio território, o jogador deixa um rastro. Ao retornar
//   a uma área que já era sua antes de iniciar o caminho, o rastro e as
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
// - Velocidade: aumenta a velocidade do jogador em 50% por 4 segundos.
//   Utilizar novamente reinicia a duração, sem acumular velocidade.
// - A partida dura 60 segundos ou termina antecipadamente quando não
//   houver casas neutras.
// - Cada casa do território vale 1 ponto. Vence quem possuir mais
//   territórios ao final da partida, podendo haver empate.
//
// Controles
//
// - Enter: começa a partida (na abertura) ou joga novamente (no resultado).
// - Setas: movimentam o personagem uma casa nas quatro direções.
// - Tecla 1: utiliza um poder de expansão armazenado.
// - Tecla 2: utiliza um poder de velocidade armazenado.

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
/// casa atual, *direcoes* guarda as direções dos movimentos e *rastro*
/// contém as casas percorridas fora do território. *casas_proprias*
/// guarda as casas próprias antes do início do rastro.
pub type Jogador {
  Jogador(
    id: Int,
    posicao: Posicao,
    direcoes: List(Direcao),
    rastro: List(Posicao),
    casas_proprias: List(Posicao),
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
}

fn cria_jogador(id: Int) -> Jogador {
  let base = base_inicial(id)

  let posicao = case id {
    1 -> Posicao(tamanho - 3, 2)
    _ -> Posicao(2, tamanho - 3)
  }

  Jogador(
    id: id,
    posicao: posicao,
    direcoes: [],
    rastro: [],
    casas_proprias: base,
    base: base,
    poderes_guardados: [],
    velocidade_extra: 0,
    velocidade: 5.0,
    reaparecimento: 0,
  )
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
    proximo_poder: 80,
    placares: [],
  )
  |> atualizar_placares
}

pub fn nova_partida_examples() {
  let partida = nova_partida()

  check.eq(list.length(partida.mapa), 400)
  check.eq(list.length(partida.jogadores), 2)
  check.eq(list.length(partida.poderes), 0)
  check.eq(partida.tiques, 0)

  let casas_jogador1 =
    list.filter(partida.mapa, fn(casa) { casa.dono == Some(1) })

  let casas_jogador2 =
    list.filter(partida.mapa, fn(casa) { casa.dono == Some(2) })

  check.eq(list.length(casas_jogador1), 9)
  check.eq(list.length(casas_jogador2), 9)
}

// ----------------------------------------------------------------------
// Teclas
// ----------------------------------------------------------------------

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

pub fn processa_tecla(estado: Estado, numero: Int, tecla: key.Event) -> Estado {
  case estado, tecla {
    Abertura(gerador, imagens), key.Enter ->
      EmPartida(gerador, imagens, nova_partida())
    Resultado(gerador, imagens, jogadores), key.Enter ->
      EmPartida(gerador, imagens, nova_partida())
    EmPartida(gerador, imagens, partida), _ ->
      case direcao(tecla) {
        Some(dir) -> EmPartida(gerador, imagens, move(partida, numero, dir))
        None -> estado
      }
    _, _ -> estado
  }
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

/// Avança um tique da partida e mostra o resultado
/// quando a duração é atingida.
pub fn avanca(gerador: Generator, imagens: ImagensPoderes, partida: Partida) {
  let tiques = partida.tiques + 1

  case tiques >= duracao, partida.proximo_poder <= 1 {
    True, _ -> Resultado(gerador, imagens, partida.placares)
    False, _ -> {
      let jogadores =
        list.map(partida.jogadores, fn(j) {
          case j.reaparecimento > 0 {
            True -> Jogador(..j, reaparecimento: j.reaparecimento - 1)
            False -> j
          }
        })

      EmPartida(
        gerador,
        imagens,
        Partida(..partida, tiques: tiques, jogadores: jogadores),
      )
    }
  }
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
}

/// Retorna a posição resultante após uma movimentação, ficando na mesma
/// posição caso o deslocamento saia do mapa
pub fn desloca(
  pos: Posicao,
  dir: Direcao,
  rastro: List(Posicao),
  base_adversario: List(Posicao),
  adversario_pos: Posicao,
) -> Posicao {
  let destino = case dir {
    Cima -> Posicao(pos.lin - 1, pos.col)
    Baixo -> Posicao(pos.lin + 1, pos.col)
    Esquerda -> Posicao(pos.lin, pos.col - 1)
    Direita -> Posicao(pos.lin, pos.col + 1)
  }

  case
    dentro_do_mapa(destino),
    contem_posicao(destino, base_adversario),
    destino == adversario_pos
  {
    True, False, False -> destino
    _, _, _ -> pos
  }
}

pub fn desloca_examples() {
  let pos = Posicao(5, 5)
  let adversario_distante = Posicao(12, 12)

  // Movimentação sem rastro.
  check.eq(desloca(pos, Cima, [], [], adversario_distante), Posicao(4, 5))
  check.eq(desloca(pos, Baixo, [], [], adversario_distante), Posicao(6, 5))
  check.eq(desloca(pos, Esquerda, [], [], adversario_distante), Posicao(5, 4))
  check.eq(desloca(pos, Direita, [], [], adversario_distante), Posicao(5, 6))

  // Movimentação nas bordas do mapa.
  let canto_superior = Posicao(0, 0)
  let canto_inferior = Posicao(19, 19)

  check.eq(
    desloca(canto_superior, Cima, [], [], adversario_distante),
    canto_superior,
  )
  check.eq(
    desloca(canto_superior, Esquerda, [], [], adversario_distante),
    canto_superior,
  )
  check.eq(
    desloca(canto_inferior, Baixo, [], [], adversario_distante),
    canto_inferior,
  )
  check.eq(
    desloca(canto_inferior, Direita, [], [], adversario_distante),
    canto_inferior,
  )

  // Movimento bloqueado pelo próprio rastro.
  check.eq(desloca(pos, Cima, [Posicao(4, 5)], [], adversario_distante), pos)
  check.eq(desloca(pos, Baixo, [Posicao(6, 5)], [], adversario_distante), pos)
  check.eq(
    desloca(pos, Esquerda, [Posicao(5, 4)], [], adversario_distante),
    pos,
  )
  check.eq(desloca(pos, Direita, [Posicao(5, 6)], [], adversario_distante), pos)

  // Movimento bloqueado por uma posição no meio do rastro.
  check.eq(
    desloca(
      pos,
      Direita,
      [Posicao(3, 3), Posicao(5, 6), Posicao(8, 8)],
      [],
      adversario_distante,
    ),
    pos,
  )

  // Movimento permitido quando o destino não pertence ao rastro.
  check.eq(
    desloca(
      pos,
      Direita,
      [Posicao(4, 5), Posicao(5, 4), Posicao(6, 5)],
      [],
      adversario_distante,
    ),
    Posicao(5, 6),
  )

  // Movimento permitido com rastro distante.
  check.eq(
    desloca(pos, Cima, [Posicao(10, 10)], [], adversario_distante),
    Posicao(4, 5),
  )

  // Movimento bloqueado quando o adversário ocupa o destino.
  check.eq(desloca(pos, Direita, [], [], Posicao(5, 6)), pos)
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
  let jogador =
    list.find(partida.jogadores, fn(j) {
      j.id == jogador_id && j.reaparecimento == 0
    })
  let adversario = list.find(partida.jogadores, fn(j) { j.id != jogador_id })

  case jogador, adversario {
    Ok(jogador), Ok(adversario) ->
      mover_jogador(partida, jogador, direcao, adversario)
    _, _ -> partida
  }
}

pub fn move_examples() {
  let partida = nova_partida()

  let movida = move(partida, 1, Cima)

  check.eq(list.map(movida.jogadores, fn(j) { j.posicao }), [
    Posicao(16, 2),
    Posicao(2, 17),
  ])

  check.eq(move(partida, 3, Cima), partida)
}

/// Reinicia o jogador após ser eliminado. Posiciona-o no centro da base,
/// limpa as direções, o rastro e os poderes guardados e restaura a
/// velocidade padrão. Preserva o território conquistado e inicia
/// a espera de dois segundos para reaparecer.
pub fn reinicia_jogador(jogador: Jogador) -> Jogador {
  let base = jogador.base
  let jogador_inicial = cria_jogador(jogador.id)
  let nova_posicao = jogador_inicial.posicao

  Jogador(
    id: jogador.id,
    posicao: nova_posicao,
    direcoes: [],
    rastro: [],
    casas_proprias: jogador.casas_proprias,
    base: base,
    poderes_guardados: [],
    velocidade_extra: 0,
    velocidade: 5.0,
    reaparecimento: 2 * tiques_por_segundo,
  )
}

pub fn reinicia_jogador_examples() {
  let inicial = cria_jogador(1)
  let jogador =
    Jogador(
      ..inicial,
      posicao: Posicao(10, 10),
      direcoes: [Cima],
      rastro: [Posicao(10, 10)],
      casas_proprias: [Posicao(15, 2), ..inicial.base],
      velocidade_extra: 10,
      velocidade: 7.5,
    )

  let reiniciado = reinicia_jogador(jogador)

  check.eq(reiniciado.id, jogador.id)
  check.eq(reiniciado.posicao, Posicao(17, 2))
  check.eq(reiniciado.base, jogador.base)
  check.eq(reiniciado.casas_proprias, jogador.casas_proprias)
  check.eq(reiniciado.direcoes, [])
  check.eq(reiniciado.rastro, [])
  check.eq(reiniciado.poderes_guardados, [])
  check.eq(reiniciado.velocidade_extra, 0)
  check.eq(reiniciado.velocidade, 5.0)
  check.eq(reiniciado.reaparecimento, 2 * tiques_por_segundo)

  let jogador_2 = cria_jogador(2)
  let reiniciado_2 =
    reinicia_jogador(Jogador(..jogador_2, posicao: Posicao(10, 10)))

  check.eq(reiniciado_2.posicao, Posicao(2, 17))
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
  let nova_pos =
    desloca(
      jogador.posicao,
      direcao,
      jogador.rastro,
      adversario.base,
      adversario.posicao,
    )

  let moveu = nova_pos != jogador.posicao
  let cortou_rastro = moveu && contem_posicao(nova_pos, jogador.rastro)
  let cortou_rastro_adversario =
    moveu && contem_posicao(nova_pos, adversario.rastro)
  let voltou_area = dono_da_casa(partida.mapa, nova_pos) == Some(jogador.id)
  let fechou_rastro = moveu && voltou_area && jogador.rastro != []

  let mapa = case fechou_rastro {
    True -> fechar_rastro(partida, jogador)
    False -> partida.mapa
  }
  let rastro = case fechou_rastro {
    True -> []
    False -> atualizar_rastro(partida, jogador, nova_pos)
  }

  let novo_jogador = case cortou_rastro {
    True -> reinicia_jogador(jogador)
    False -> Jogador(..jogador, posicao: nova_pos, rastro: rastro)
  }
  let novo_adversario = case cortou_rastro_adversario {
    True -> reinicia_jogador(adversario)
    False -> adversario
  }

  let jogadores =
    list.map(partida.jogadores, fn(j) {
      case j.id == jogador.id {
        True -> novo_jogador
        False -> novo_adversario
      }
    })

  let atualizada = Partida(..partida, mapa: mapa, jogadores: jogadores)

  case fechou_rastro {
    True -> atualizar_placares(atualizada)
    False -> atualizada
  }
}

/// Conquista o rastro e as casas cercadas ao voltar
/// ao território do jogador.
pub fn fechar_rastro(partida: Partida, jogador: Jogador) -> List(Casa) {
  let mascara = criar_mascara(partida, jogador)
  let mascara = casas_exteriores(mascara)

  pintar_mapa(partida.mapa, mascara, jogador.id)
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

/// Retorna True se a posição *pos* já está em *posicoes*,
/// Retorna False caso contrário.
pub fn contem_posicao(pos: Posicao, posicoes: List(Posicao)) -> Bool {
  case posicoes {
    [] -> False
    [p, ..resto] -> p == pos || contem_posicao(pos, resto)
  }
}

/// Adiciona a posição *pos* na lista *rastro*. Caso a
/// posição já esteja na lista, não muda o rastro
pub fn adicionar_rastro(pos: Posicao, rastro: List(Posicao)) -> List(Posicao) {
  case contem_posicao(pos, rastro) {
    True -> rastro
    False -> [pos, ..rastro]
  }
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

/// Devolve as posições vizinhas que ficam dentro do mapa.
pub fn casas_vizinhas(pos: Posicao) -> List(Posicao) {
  let candidatas = [
    Posicao(pos.lin - 1, pos.col),
    Posicao(pos.lin + 1, pos.col),
    Posicao(pos.lin, pos.col - 1),
    Posicao(pos.lin, pos.col + 1),
  ]

  list.filter(candidatas, dentro_do_mapa)
}

/// Cria a máscara na mesma ordem das casas do mapa.
/// O território e o rastro do jogador formam a barreira.
/// As outras casas começam como não exploradas.
pub fn criar_mascara(partida: Partida, jogador: Jogador) -> List(EstadoCasa) {
  list.map(partida.mapa, fn(casa) {
    case
      casa.dono == Some(jogador.id)
      || contem_posicao(casa.posicao, jogador.rastro)
    {
      True -> TerritorioOuRastro
      False -> NaoExplorada
    }
  })
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

/// Devolve o elemento no índice *indice*. Caso
/// o índice não existir, devolve *default*
pub fn consultar_indice(lista: List(a), indice: Int, default: a) -> a {
  case lista, indice {
    [primeiro, ..], 0 -> primeiro
    [_, ..resto], n if n > 0 -> consultar_indice(resto, n - 1, default)
    _, _ -> default
  }
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

/// Encontra o trecho não explorado que contém pos
pub fn encontrar_trecho(mascara: List(EstadoCasa), pos: Posicao) -> Trecho {
  Trecho(
    linha: pos.lin,
    inicio: limite_trecho(mascara, pos, Esquerda),
    fim: limite_trecho(mascara, pos, Direita),
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

/// Percorre a máscara a partir de indice, colocando True
/// entre inicio e fim.
pub fn marcar_intervalo(
  mascara: List(EstadoCasa),
  indice: Int,
  inicio: Int,
  fim: Int,
) -> List(EstadoCasa) {
  case indice > fim {
    True -> mascara
    False -> {
      case mascara {
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
  }
}

/// Devolve uma posição por grupo não explorado na linha
/// *linha*, entre as colunas inicial e final do trecho.
pub fn conexoes_linha(
  mascara: List(EstadoCasa),
  trecho: Trecho,
  linha: Int,
) -> List(Posicao) {
  procurar_conexoes(mascara, linha, trecho.inicio, trecho.fim, True, [])
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

          let acima = conexoes_linha(mascara, trecho, trecho.linha - 1)
          let abaixo = conexoes_linha(mascara, trecho, trecho.linha + 1)

          let pendentes =
            list.fold(acima, resto, fn(lista, pos) { [pos, ..lista] })

          let pendentes =
            list.fold(abaixo, pendentes, fn(lista, pos) { [pos, ..lista] })

          scanline_fill(mascara, pendentes)
        }
      }
    }
  }
}

/// Marca as casas alcançáveis pelas quatro bordas,
/// sem atravessar o território nem o rastro do jogador.
pub fn casas_exteriores(mascara: List(EstadoCasa)) -> List(EstadoCasa) {
  let bordas = bordas_livres(mascara)
  scanline_fill(mascara, bordas)
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

// ----------------------------------------------------------------------
// Flood Fill - Examples
// ----------------------------------------------------------------------

pub fn vizinhas_examples() {
  check.eq(casas_vizinhas(Posicao(0, 0)), [
    Posicao(1, 0),
    Posicao(0, 1),
  ])

  check.eq(casas_vizinhas(Posicao(5, 5)), [
    Posicao(4, 5),
    Posicao(6, 5),
    Posicao(5, 4),
    Posicao(5, 6),
  ])
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

pub fn consultar_indice_examples() {
  check.eq(consultar_indice([10, 20, 30], 1, 0), 20)
  check.eq(consultar_indice([10], 3, 0), 0)
  check.eq(consultar_indice([], 0, 0), 0)
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

  check.eq(bordas_livres([TerritorioOuRastro]), [])
}

pub fn limite_trecho_examples() {
  let mascara = [
    TerritorioOuRastro,
    NaoExplorada,
    NaoExplorada,
    NaoExplorada,
    TerritorioOuRastro,
  ]

  check.eq(limite_trecho(mascara, Posicao(0, 2), Esquerda), 1)
  check.eq(limite_trecho(mascara, Posicao(0, 2), Direita), 3)

  // Para na borda esquerda
  check.eq(limite_trecho([NaoExplorada], Posicao(0, 0), Esquerda), 0)
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

pub fn marcar_trecho_examples() {
  check.eq(
    marcar_trecho(
      [NaoExplorada, NaoExplorada, NaoExplorada],
      Trecho(linha: 0, inicio: 1, fim: 2),
    ),
    [NaoExplorada, Exterior, Exterior],
  )
}

pub fn marcar_intervalo_examples() {
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

  check.eq(marcar_intervalo([], 0, 0, 1), [])
}

pub fn conexoes_linha_examples() {
  let mascara = [
    NaoExplorada,
    NaoExplorada,
    TerritorioOuRastro,
    NaoExplorada,
  ]

  let trecho = Trecho(linha: 1, inicio: 0, fim: 3)

  // Uma posição por grupo, acumuladas pelo começo da lista.
  check.eq(conexoes_linha(mascara, trecho, 0), [
    Posicao(0, 3),
    Posicao(0, 0),
  ])

  check.eq(conexoes_linha(mascara, trecho, -1), [])
}

pub fn procurar_conexoes_examples() {
  check.eq(procurar_conexoes([NaoExplorada, NaoExplorada], 0, 0, 1, True, []), [
    Posicao(0, 0),
  ])

  // Já estamos dentro de um grupo registrado.
  check.eq(
    procurar_conexoes([NaoExplorada, NaoExplorada], 0, 0, 1, False, []),
    [],
  )
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

pub fn casas_exteriores_examples() {
  // Os dois grupos estão na borda e devem ser explorados.
  check.eq(
    casas_exteriores([
      NaoExplorada,
      TerritorioOuRastro,
      NaoExplorada,
    ]),
    [
      Exterior,
      TerritorioOuRastro,
      Exterior,
    ],
  )
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
    // Exterior mantém o dono.
    Casa(Posicao(0, 0), Some(2)),
    // Rastro fica com o jogador.
    Casa(Posicao(0, 1), Some(1)),
    // Casa cercada é conquistada.
    Casa(Posicao(0, 2), Some(1)),
  ])
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
}

/// Produz a cor de uma casa conforme seu proprietário.
fn cor_casa(dono: Option(Int)) -> Color {
  case dono {
    Some(1) -> color.green
    Some(2) -> color.blue
    _ -> color.white
  }
}

/// Produz a cor de um rastro conforme seu proprietário.
fn cor_rastro(dono: Option(Int)) -> Color {
  case dono {
    Some(1) -> color.springgreen
    Some(2) -> color.powderblue
    _ -> color.white
  }
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

fn desenha_rastro(id: Int) -> Image {
  image.square(lado_casa, style.fill(cor_rastro(Some(id))))
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
pub fn grade(partida: Partida) -> Image {
  let fundo =
    image.rectangle(
      tamanho * lado_casa,
      tamanho * lado_casa,
      style.fill(color.white),
    )

  let com_casas =
    list.fold(partida.mapa, fundo, fn(cena, casa) {
      coloca_img(cena, casa.posicao, desenha_casa(casa))
    })

  let com_rastro =
    list.fold(partida.jogadores, com_casas, fn(cena, j) {
      list.fold(j.rastro, cena, fn(imagem, pos) {
        coloca_img(imagem, pos, desenha_rastro(j.id))
      })
    })

  list.fold(partida.jogadores, com_rastro, fn(cena, j) {
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
  _imagens: ImagensPoderes,
  partida: Partida,
  id: Int,
) -> Image {
  let segundos =
    { duracao - partida.tiques + tiques_por_segundo - 1 } / tiques_por_segundo

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

  let tabuleiro = grade(partida)

  let tabuleiro = case
    list.find(partida.jogadores, fn(j) { j.id == id && j.reaparecimento > 0 })
  {
    Ok(jogador) -> {
      let segundos_restantes =
        { jogador.reaparecimento + tiques_por_segundo - 1 } / tiques_por_segundo

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

    Error(_) -> tabuleiro
  }

  image.above(
    image.above(
      image.text("Tempo: " <> int.to_string(segundos) <> " s", 24, fill.black),
      placar,
    ),
    tabuleiro,
  )
}

/// Mostra os placares finais e permite reiniciar.
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
    image.text("Fim da partida", 32, fill.black),
    image.above(
      placar,
      image.text("Pressione Enter para jogar novamente", 20, fill.black),
    ),
  )
}
