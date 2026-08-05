# Monthly crime trends: a global STL-style decomposition

This paper decomposes monthly crime counts for every city in the RTCI national
sample. The current output contains 458,392 valid city-month-crime observations
from 586 cities and uses no population threshold.

Rates are annualized from monthly counts:

`annualized rate = monthly count / population * 100,000 * 12`

This puts murder on the familiar annual scale; the current sample’s average
monthly population-weighted murder rate is about 7.92 per 100,000.

## Model

The stacked model uses an aggregated-binomial logit response for murder, rape,
robbery, assault, burglary, theft, and motor-vehicle theft. It estimates a
crime-specific smooth time trend, a smooth year term, and a cyclic month
effect. The global STL-style output contains:

- observed population-weighted rate;
- smooth trend;
- trend plus cyclic seasonal effect;
- seasonal rate change from trend.

For every city, crime type, and month, `overdispersion_logit` is the logit-scale
departure of the observed cell from the city/crime baseline. It is retained in
full and is not filtered using Pearson residuals or an arbitrary threshold.

## Figures

The rendered figures and full paper are in [paper.pdf](paper.pdf). The local
app provides the interactive Global STL, City detail, and City map views.

