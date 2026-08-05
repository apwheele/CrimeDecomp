# Monthly crime trends: a global STL-style decomposition

This descriptive analysis decomposes monthly crime counts for every city in
the RTCI national sample into a smooth crime-specific trend, a cyclic seasonal
component, and residual departures.

Rates are annualized from monthly counts: `12 * count / population * 100,000`.
The current sample contains 458,392 valid city-month-crime observations from
586 cities, with no population threshold. The average observed murder rate in
the sample is about 7.92 per 100,000 on this annualized scale.

The PDF contains three global figures, each with one panel per crime type:

1. Global trend.
2. Global seasonal component.
3. Centered global residual.

The app data also contain the complete city-by-crime-by-month term
`overdispersion_logit`. It is the logit departure of the observed city cell
from its fitted city baseline, centered at zero within each city and crime
type. It is not a Pearson residual and is not filtered by a threshold.
