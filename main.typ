#import "template.typ": template

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
#include "preliminaries.typ"
#include "architecture.typ"
#include "evaluation.typ"
#include "future_work.typ"
#include "conclusion.typ"
