# Monthly crime trends: a global STL-style decomposition

This descriptive analysis decomposes monthly crime counts for every city in
the RTCI national sample into a smooth crime-specific trend, a cyclic seasonal
component, and residual departures.

Rates are annualized from monthly counts. A monthly count (Y) in population
(N) is displayed as (12Y/N \times 100,000). The current sample contains
458,392 valid city-month-crime observations from 586 cities, with no population
threshold. The average observed murder rate is about 7.92 per 100,000.

The project uses one aggregated-binomial mixed model:

$$
Y_{ict} \sim \operatorname{Binomial}(N_i,p_{ict}),
\qquad
\operatorname{logit}(p_{ict}) = \alpha_c + f_c(t) + s_c(m_t) + b_i,
\quad b_i \sim N(0,\sigma_b^2).
$$

The smooth trend and cyclic seasonal effect are global crime-specific terms;
the city random intercept is included for city predictions and excluded for
global predictions. The city-by-crime-by-month overdispersion term is the
observed cell departure from the city prediction, centered at zero within each
city and crime type. It is not a Pearson residual.

The PDF contains three global figures, each with one panel per crime type:

1. Global trend.
2. Global seasonal component.
3. Centered global residual.

A declining murder trend and positive recent residuals are compatible. The
trend is the smooth long-run baseline; a positive residual means recent
observations are above that declining baseline.
