#import "template.typ": template
#import "utils.typ": todo

#let title = "High-performance 2D graphics rendering on the CPU using sparse strips"
#let thesis_type = "Master Thesis"
#let author = "Laurenz Stampfl"
#let advisors = (
  "Prof. Dr. Ralf Jung",
  "Dr. Raph Levien" 
)
#let department = "Department of Computer Science, ETH Zürich"

#show: doc => template(
  title,
  thesis_type,
  author,
  advisors,
  department,
  doc
)

#include "introduction.typ"
#include "background/main.typ"
#include "implementation/main.typ"
#include "comparison/main.typ"
#include "evaluation/main.typ"
#include "conclusion.typ"
