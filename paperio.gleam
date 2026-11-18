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
/// contém as casas percorridas fora do território. *casas_proprias6*
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
    1 -> sequencia(1, 3)
    2 -> sequencia(tamanho - 4, tamanho - 2)
    _ -> []
  }

  let linhas = case id {
    1 -> sequencia(tamanho - 4, tamanho - 2)
    2 -> sequencia(1, 3)
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
    False, _ -> EmPartida(gerador, imagens, Partida(..partida, tiques: tiques))
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

/// Retorna a posição resultante após uma movimentação, ficando na mesma
/// posição caso o deslocamento saia do mapa
pub fn desloca(pos: Posicao, dir: Direcao, rastro: List(Posicao)) -> Posicao {
  let destino = case dir {
    Cima -> Posicao(pos.lin - 1, pos.col)
    Baixo -> Posicao(pos.lin + 1, pos.col)
    Esquerda -> Posicao(pos.lin, pos.col - 1)
    Direita -> Posicao(pos.lin, pos.col + 1)
  }

  case dentro_do_mapa(destino), tem_rastro(destino, rastro) {
    True, False -> destino
    _, _ -> pos
  }
}

/// Devolve o dono da casa na posição pos.
/// Devolve None se a casa for neutra ou não estiver no mapa.
pub fn dono_da_casa(mapa: List(Casa), pos: Posicao) -> Option(Int) {
  case list.find(mapa, fn(casa) { casa.posicao == pos }) {
    Ok(casa) -> casa.dono
    Error(_) -> None
  }
}

/// Move o jogador na direção escolhida. Se ele estiver esperando 
/// para reaparecer, mantém a partida sem alterações.
pub fn move(partida: Partida, jogador_id: Int, direcao: Direcao) -> Partida {
  case
    list.find(partida.jogadores, fn(j) {
      j.id == jogador_id && j.reaparecimento == 0
    })
  {
    Error(_) -> partida
    Ok(jogador) -> mover_jogador(partida, jogador, direcao)
  }
}

/// Atualiza a posição e o rastro do jogador.
/// Se ele voltar ao próprio território com um rastro,
/// transforma o caminho em território e limpa o rastro.
pub fn mover_jogador(
  partida: Partida,
  jogador: Jogador,
  direcao: Direcao,
) -> Partida {
  let nova_pos = desloca(jogador.posicao, direcao, jogador.rastro)
  let voltou = dono_da_casa(partida.mapa, nova_pos) == Some(jogador.id)

  let fecha = nova_pos != jogador.posicao && voltou && jogador.rastro != []

  let mapa = case fecha {
    True -> fechar_rastro(partida, jogador)
    False -> partida.mapa
  }

  let rastro = case fecha {
    True -> []
    False -> atualizar_rastro(partida, jogador, nova_pos)
  }

  let jogadores =
    list.map(partida.jogadores, fn(j) {
      case j.id == jogador.id {
        True -> Jogador(..j, posicao: nova_pos, rastro: rastro)
        False -> j
      }
    })

  Partida(..partida, mapa: mapa, jogadores: jogadores)
  |> atualizar_placares
}

/// Fecha o rastro do jogador, ao voltar ao uma casa sua
pub fn fechar_rastro(partida: Partida, jogador: Jogador) -> List(Casa) {
  list.map(partida.mapa, fn(casa) {
    case tem_rastro(casa.posicao, jogador.rastro) {
      True -> Casa(..casa, dono: Some(jogador.id))
      False -> casa
    }
  })
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

/// Retorna True se a posição *pos* já está no *rastro*,
/// Retorna False caso contrário.
pub fn tem_rastro(pos: Posicao, rastro: List(Posicao)) -> Bool {
  case rastro {
    [] -> False
    [p, ..resto] -> p == pos || tem_rastro(pos, resto)
  }
}

/// Adiciona a posição *pos* na lista *rastro*. Caso a
/// posição já esteja na lista, não muda o rastro
pub fn adicionar_rastro(pos: Posicao, rastro: List(Posicao)) -> List(Posicao) {
  case tem_rastro(pos, rastro) {
    True -> rastro
    False -> [pos, ..rastro]
  }
}

// ----------------------------------------------------------------------
// Posições e movimentação - Exemplos
// ----------------------------------------------------------------------

pub fn dentro_do_mapa_examples() {
  check.eq(dentro_do_mapa(Posicao(0, 0)), True)
  check.eq(dentro_do_mapa(Posicao(19, 19)), True)
  check.eq(dentro_do_mapa(Posicao(-1, 5)), False)
  check.eq(dentro_do_mapa(Posicao(20, 5)), False)
}

pub fn desloca_examples() {
  // Movimentação sem rastro.
  check.eq(desloca(Posicao(5, 5), Cima, []), Posicao(4, 5))
  check.eq(desloca(Posicao(5, 5), Baixo, []), Posicao(6, 5))
  check.eq(desloca(Posicao(5, 5), Esquerda, []), Posicao(5, 4))
  check.eq(desloca(Posicao(5, 5), Direita, []), Posicao(5, 6))

  // Movimentação nas bordas do mapa.
  check.eq(desloca(Posicao(0, 0), Cima, []), Posicao(0, 0))
  check.eq(desloca(Posicao(0, 0), Esquerda, []), Posicao(0, 0))
  check.eq(desloca(Posicao(19, 19), Baixo, []), Posicao(19, 19))
  check.eq(desloca(Posicao(19, 19), Direita, []), Posicao(19, 19))

  // Movimento bloqueado pelo próprio rastro.
  check.eq(desloca(Posicao(5, 5), Cima, [Posicao(4, 5)]), Posicao(5, 5))
  check.eq(desloca(Posicao(5, 5), Baixo, [Posicao(6, 5)]), Posicao(5, 5))
  check.eq(desloca(Posicao(5, 5), Esquerda, [Posicao(5, 4)]), Posicao(5, 5))
  check.eq(desloca(Posicao(5, 5), Direita, [Posicao(5, 6)]), Posicao(5, 5))

  // Movimento bloqueado por uma posição no meio do rastro.
  check.eq(
    desloca(Posicao(5, 5), Direita, [
      Posicao(3, 3),
      Posicao(5, 6),
      Posicao(8, 8),
    ]),
    Posicao(5, 5),
  )

  // Movimento permitido quando o destino não pertence ao rastro.
  check.eq(
    desloca(Posicao(5, 5), Direita, [
      Posicao(4, 5),
      Posicao(5, 4),
      Posicao(6, 5),
    ]),
    Posicao(5, 6),
  )

  // Movimento permitido com rastro distante.
  check.eq(desloca(Posicao(5, 5), Cima, [Posicao(10, 10)]), Posicao(4, 5))
}

pub fn dono_da_casa_examples() {
  let partida = nova_partida()

  check.eq(dono_da_casa(partida.mapa, Posicao(17, 2)), Some(1))
  check.eq(dono_da_casa(partida.mapa, Posicao(2, 17)), Some(2))
  check.eq(dono_da_casa(partida.mapa, Posicao(10, 10)), None)
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
    coloca_img(cena, j.posicao, desenha_jogador(j))
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

  image.above(
    image.above(
      image.text("Tempo: " <> int.to_string(segundos) <> " s", 24, fill.black),
      placar,
    ),
    grade(partida),
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
