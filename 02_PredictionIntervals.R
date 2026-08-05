#https://cran.r-project.org/web/packages/rstanarm/index.html
#see https://cran.r-project.org/web/packages/rstanarm/vignettes/pooling.html
#and https://cran.r-project.org/web/packages/rstanarm/vignettes/count.html

#prediction intervals
#https://cran.r-project.org/web/packages/merTools/vignettes/Using_predictInterval.html
#https://biologyforfun.wordpress.com/2015/06/17/confidence-intervals-for-prediction-in-glmms/

#maybe beta-binomial regression, http://varianceexplained.org/r/ebbr-package/
#non-linear spline of Year and/or population size?


#library(rstanarm)
#library(ggplot2)
library(lme4)
#library(MASS)
library(merTools)
library(arm)

set.seed(10)
#options(mc.cores = parallel::detectCores()) #defaults to 4 otherwise it appears

#read in the data
#note that the slashes need to be escaped in R
mydir <- "C:\\Users\\axw161530\\Box Sync\\Projects\\HomicideGraphs\\Analysis\\Analysis" 
setwd(mydir)

#read in CSV file
HomData <- read.csv(file="HomRate.csv",header=TRUE)
summary(HomData)
HomData$HomRate <- (HomData$Homicide/HomData$Pop1)*100000
#turn ORI and ?Year? into factors

#fact <- table(HomData$ORI)
#subset <- sample(fact,size=100)
#subORI <- rownames(subset)
#sum(HomData$ORI %in% subORI)
#NewSet <- HomData[HomData$ORI %in% subORI,]
#NewSet <- HomData[HomData$Year >= 2013,]
#length(NewSet$Year)
#Stan code, did not run overnight even on the subset of the data
#Priors on the coefficients?
#NB_1 <- stan_glmer(Homicide ~ (1|Year) + (1|ORI), offset=log(Pop1), family=neg_binomial_2, data=NewSet)
#yrep <- posterior_predict(NB_1)
#NB_1
#Sys.time()
#HomRan <- glmer.nb(Homicide ~ (1|Year) + (1|ORI), offset=log(Pop1), data=HomData)
#summary(HomRan)
#Sys.time()

#PI <- predictInterval(merMod = HomRan, newdata = NewData,
#                        level = 0.90, n.sims = 100,
#                        stat = "mean", type="linear.prediction")
						
						
#binomial model
#HomData$YearFact <- as.factor(HomData$Year) #meh some experiments fixed effect for years is taking too long
#NewData <- HomData[HomData$Year == 2014,]
#NewData$Year <- 2015

#Mixed effects Logistic regression model
#normal binomial
#HomRanBin <- glmer(cbind(Homicide,Pop1 - Homicide) ~ (1|Year) + (1|ORI), binomial, data=HomData)
#overdispersed binomial, http://r.789695.n4.nabble.com/Question-on-overdispersion-td3049898.html

MaxPop <- aggregate(Pop1 ~ ORI, data=HomData, max)
BigPop <- MaxPop[MaxPop$Pop1 >= 100000,]
BigCit <- HomData[HomData$ORI %in% BigPop$ORI,]
HomRanBin <- glmer(cbind(Homicide,Pop1 - Homicide) ~ (1|Year) + (1|ORI) + (1|Row), binomial, data=BigCit)
HomRanBin

#HomRanLogPop <- glmer(cbind(Homicide,Pop1 - Homicide) ~ log(Pop1) + (1|Year) + (1|ORI) + (1|Row), binomial, data=BigCit)
#HomRanLogPop

RE_HomRanBin <- REextract(HomRanBin)

#Now adding in additional components, global intercept
fix <- coef(summary(HomRanBin))
RE_HomRanBin$GlobInt <- fix[1]
RE_HomRanBin$GlobIntSE <- fix[2]

#Now adding in the random variances for 
varRE <- data.frame(VarCorr(HomRanBin))
RE_HomRanBin$SD_Row <- varRE[1,5]
RE_HomRanBin$SD_ORI <- varRE[2,5]
RE_HomRanBin$SD_Year <- varRE[3,5]

#These are the random effects that should be centered at zero
head(RE_HomRanBin)
head(ranef(HomRanBin)$Row)

write.csv(RE_HomRanBin,file='RandomEffects_HomRanBin.csv', row.names=FALSE)
write.csv(BigCit,file="BigCitiesOnly.csv", row.names=FALSE)

#HomData$YearFact <- as.factor(HomData$Year) #meh some experiments fixed effect for years is taking too long
#HomFixYear <- glmer(cbind(Homicide,Pop1 - Homicide) ~ YearFact + (1|ORI), binomial, data=HomData)
#HomFixYear

for (i in 1:10){
  SimRes <- sim(HomRanBin, 100)
  ArmRes <- data.frame(fitted(SimRes,HomRanBin))
  write.csv(ArmRes,file=paste0("ArmSim100_",toString(i),".csv"), row.names=TRUE)
  }

#Check out full distribution for one city, Dallas
DallasSub <- BigCit[BigCit$ORI == 'TXDPD00',]
PI_Dallas <- predictInterval(merMod = HomRanBin, newdata = DallasSub,
                        level = 0.95, n.sims = 1000, which= "all",
                        stat = "median", type="probability", returnSims=FALSE,
						include.resid.var = TRUE)

PI_Dallas2 <- data.frame(PI_Dallas)
PI_Dallas2$fit <- PI_Dallas$fit*100000
PI_Dallas2$upr <- PI_Dallas$upr*100000
PI_Dallas2$lwr <- PI_Dallas$lwr*100000
PI_Dallas2
#Not sure what is up with the random effects part, it is clearly not on the same scale
#cbind(PI_Dallas,1/(1 + (exp(-1*PI_Dallas$fit)))

						


#Too big to do the prediction intervals all at once
#MaxPop <- aggregate(Pop1 ~ ORI, data=HomData, max)
#BigPop <- MaxPop[MaxPop$Pop1 >= 50000,]
#BigCit <- HomData[HomData$ORI %in% BigPop$ORI,]
#PI <- predictInterval(merMod = HomRanBin, newdata = BigCit,
#                        level = 0.90, n.sims = 1000, which="full",
#                        stat = "mean", type="probability")
#IntData <- cbind(PI*100000,BigCit)
#write.csv(IntData,file="PredictInt_Big.csv", row.names=FALSE)

			
#Now for the smaller cities
#Still too big for R!!!!!!!!!!
#SmallPop <- MaxPop[MaxPop$Pop1 >= 50000,]
#SmallCit <- HomData[HomData$ORI %in% SmallPop$ORI,]
#It is pretty big, about 450,000
#PI_s <- predictInterval(merMod = HomRanBin, newdata = SmallCit,
#                        level = 0.90, n.sims = 1000,
#                        stat = "mean", type="probability")
#
#IntDataS <- cbind(PI_s*100000,SmallCit)
#IntDataS$HomRate <- (SmallCit$Homicide/SmallCit$Pop1)*100000
#IntDataS
#write.csv(IntDataS,file="PredictInt_Small.csv", row.names=FALSE)

#Now intervals based on posterior simulations in arm
gc()
format(object.size(HomData),units="Mb")
rm("DallasSub","mydir","PI_Dallas","PI_Dallas2","HomData")
#SimRes <- sim(HomRanBin, 1000) #can do this, but the fitted object is too large
HomRanBin@frame <- HomRanBin@frame[1,] #stripping data frame within HomRanBin

#for (i in 1:10){
#  SimRes <- sim(HomRanBin, 100)
#  ArmRes <- data.frame(fitted(SimRes,HomRanBin))
#  write.csv(ArmRes,file=paste0("ArmSim100_",toString(i),".csv"), row.names=TRUE)
#  }

#Will need to calculate quantiles myself in SPSS



  

#ArmRes <- data.frame(fitted(SimRes,HomRanBin))
#HomData$FitMed <- apply(ArmRes, 1, median)
#HomData$FitHigh99 <- apply(ArmRes, 1, function(x) quantile(x, 0.990))
#HomData$FitHigh95 <- apply(ArmRes, 1, function(x) quantile(x, 0.950))
#HomData$FitHigh90 <- apply(ArmRes, 1, function(x) quantile(x, 0.900))
#HomData$FitHigh75 <- apply(ArmRes, 1, function(x) quantile(x, 0.750))
#HomData$FitLow25 <- apply(ArmRes, 1, function(x) quantile(x, 0.250))
#HomData$FitLow10 <- apply(ArmRes, 1, function(x) quantile(x, 0.100))
#HomData$FitLow05 <- apply(ArmRes, 1, function(x) quantile(x, 0.050))
#HomData$FitLow01 <- apply(ArmRes, 1, function(x) quantile(x, 0.010))
#write.csv(HomData,file="ArmSim_1000.csv", row.names=FALSE)

