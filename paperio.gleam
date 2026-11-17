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
const altura = 480

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
type Casa {
  Casa(posicao: Posicao, dono: Option(Int))
}

/// Os tipos de poderes que podem ser utilizados pelos jogadores.
type TipoPoder {
  Expansao
  Velocidade
}

pub type ImagensPoderes {
  ImagensPoderes(velocidade: Image, expansao: Image)
}

/// Um poder disponível no mapa. *tipo* indica o efeito do poder e
/// *posicao* indica a casa em que ele pode ser coletado.
type PoderNoMapa {
  PoderNoMapa(tipo: TipoPoder, posicao: Posicao)
}

/// Um jogador da partida. *id* identifica o jogador, *posicao* indica sua
/// casa atual, *direcoes* guarda as direções dos movimentos e *rastro*
/// contém as casas percorridas fora do território. *casas_proprias6*
/// guarda as casas próprias antes do início do rastro.
type Jogador {
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
type Partida {
  Partida(
    mapa: List(Casa),
    jogadores: List(Jogador),
    poderes: List(PoderNoMapa),
    tiques: Int,
    proximo_poder: Int,
  )
}

/// A pontuação de um jogador. *jogador* indica seu número e *casas*
/// representa a quantidade de casas que ele controla.
type Placar {
  Placar(jogador: Int, casas: Int)
}

/// O estado do jogo. Todos os estados guardam o gerador de números
/// aleatórios utilizado durante a partida.
type Estado {
  /// Antes da primeira partida.
  Abertura(gerador: random.Generator)
  /// Durante uma partida.
  EmPartida(gerador: random.Generator, partida: Partida)
  /// Depois de uma partida, com a pontuação dos jogadores.
  Resultado(gerador: random.Generator, placares: List(Placar))
}

// ----------------------------------------------------------------------
// Mundo
// ----------------------------------------------------------------------

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

// ----------------------------------------------------------------------
// Tiques
// ----------------------------------------------------------------------

pub fn todas_as_casas_examples() {
  check.eq(list.length(todas_as_casas()), 100)
  check.eq(list.first(todas_as_casas()), Ok(Posicao(0, 0)))
  check.eq(list.last(todas_as_casas()), Ok(Posicao(9, 9)))
}