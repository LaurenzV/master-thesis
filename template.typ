#import "@preview/hydra:0.6.2": hydra

#let thin_line = line(length: 100%, stroke: 0.6pt)

#let template(
  title,
  thesis_type,
  author,
  advisors,
  department,
  doc,
) = [
  #set page(margin: (x: 3.2cm, y: 4.5cm))

  #image("assets/eth_logo.pdf", width: 5cm)

  #v(3.5cm)

  #set align(center)
  #set text(font: "New Computer Modern Sans", size: 16pt)

  #par(leading: 0.35cm)[
    #text(weight: "bold", size: 25pt)[#title]
  ]

  #v(1.5cm)

  #thesis_type

  #author

  #datetime.today().display("[month repr:long] [day], [year]")

  #v(1fr)

  #set align(right)
  #set text(size: 11pt)

  Advisors: #advisors.join(", ")

  #department

  #pagebreak()

  #set page(numbering: "i", number-align: right)
  #counter(page).update(1)

  #set align(left)
  #set par(justify: true)
  #set text(font: "PT Serif", size: 11pt)
  #set page(margin: (x: 3.5cm, y: 4.5cm))

  #v(0.3cm)

  #align(center)[*Abstract*]

  #thin_line
  #include "abstract.typ"

  #pagebreak()

  #align(center)[*Acknowledgements*]

  #thin_line
  #include "acknowledgements.typ"

  #pagebreak()
  
  #set page(
    header: context [
      #let chapters = query(
      heading.where(
        level: 1
      ))
      #let show_line = true
      #let cur_page = counter(page).at(here())
      #for chapter in chapters [
        #let loc = chapter.location()

        #if counter(page).at(loc) == cur_page {
          show_line = false
        }
      ]

      #hydra(2, display: (_, it) => {
        set align(right)
        numbering(it.numbering, ..counter(heading).at(it.location()))
        it.body

        thin_line
      })
    ]
  )
  
  #set heading(numbering: none)
  #show heading: it => {
    set text(font: "New Computer Modern Sans")

    if it.level == 1 [
      #set align(center)
      #set block(spacing: 0.6cm)

      #pagebreak(weak: true)
      #context {
        if heading.numbering != none  [
          #let heading_num = counter(heading).at(here()).at(0)
          Chapter #heading_num
        ]
      }
      
      #thin_line
      #text(size: 1.5em)[#it.body]
      #thin_line
    ] else [
      #set text(size: 1.2em)
      #it
    ]
  }

  #show outline: set heading(outlined: true)
  #show outline.entry.where(level: 1): it => {
    show repeat: none
    v(0.4cm)
    strong(it)
  }

  #[
    #show heading: it => {
      it
      v(0.5cm)
    }
    
    #outline(depth: 3)
  ]

  #set heading(numbering: (..nums) => nums.pos().map(str).join("."))
  
  #set page(numbering: "1")
  #counter(page).update(1)

  #doc

  #set heading(numbering: none)

  #bibliography("refs.bib")

  #set page(margin: 0pt)
  #image("assets/declaration.pdf")
]
