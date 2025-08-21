#let mid-fig(width: 100%, contents) = {
  set align(center)
  
  box(width: width)[#contents]
}

#let todo(t) = text(fill: red)[#strong[TODO: #t]]