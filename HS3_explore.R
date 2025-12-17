##########################################################
# Created by: Pascale Goertler (pascale.goertler@water.ca.gov)
# Last updated: 12/17/2025
# Description: This script pulls in data from EDI and evaluates data using diagnostics from Zuur et al. 2010
# Intended to explore Feather River data use in Science Plan hypothesis S3
#########################################################
## HS3
## The density of salmonid redds will increase in habitat enhancement areas compared to proximate, non-enhanced areas

# library
library(EDIutils)
library(lattice)
library(car)

# get data
temp <- read_data_entity_names(packageId = "edi.1802.2")
temp_dat <- read_data_entity(packageId = "edi.1802.2", entityId = temp$entityId[1])
data <- readr::read_csv(file = temp_dat)

# view data
head(data)
str(data)
summary(data)

# to get to redd density we need to have stream lengths and/or project area by site
location <- unique(data$location) #49 sites
size = NA
ref = NA
dat_location <- cbind(location, size, ref) # for meeting in Jan 2026
# write.csv(dat_location, "need_loc_detail.csv")

# add month, year and water year
data$month <- format(as.Date(data$date), "%m")
data$year <- format(as.Date(data$date), "%Y")

dates.posix <- as.POSIXlt(data$date)
offset <- ifelse(dates.posix$mon >= 10 - 1, 1, 0)

#water year
data$water_year <- dates.posix$year + 1900 + offset

# outliers
boxplot(data$number_redds)
dotchart(data$number_redds)

boxplot(data$number_salmon) # need to ask what NA salmon means...
dotchart(data$number_salmon)

#distribution
hist(data$number_redds)
hist(data$number_salmon)

histogram( ~ number_redds | location, data = data)
histogram( ~ number_salmon | location, data = data)

histogram( ~ number_redds | year, data = data)
histogram( ~ number_salmon | year, data = data)

histogram( ~ number_redds | water_year, data = data)
histogram( ~ number_salmon | water_year, data = data)

histogram( ~ number_redds | month, data = data)
histogram( ~ number_salmon | month, data = data)

# homogeneity of variance
full_model_redds <- lm(number_redds ~ date + location + depth_m + pot_depth_m + velocity_m_s +
                         percent_fines + percent_small + percent_med + percent_large + percent_boulder +
                         redd_width_m + redd_length_m, data)
full_model_salmon <- lm(number_salmon ~ date + location + depth_m + pot_depth_m + velocity_m_s +
                      percent_fines + percent_small + percent_med + percent_large + percent_boulder +
                      redd_width_m + redd_length_m, data)

plot(resid(full_model_redds))
plot(resid(full_model_salmon))

bwplot(number_redds ~ boat_point | location, data = data)
# ask about location, will want to break up by type - restored, reference, etc. (then rerun)
bwplot(number_redds ~ month | location, data = data)
bwplot(number_redds ~ month | year, data = data)

bwplot(number_salmon ~ month | location, data = data)
bwplot(number_salmon ~ month | year, data = data)

# zeros
dat_rmnas <- data[!is.na(data$number_redds),]
dat_rmnas <- data[!is.na(data$number_salmon),]

plot(table(round(dat_rmnas$number_redds * dat_rmnas$number_redds)),
     type = "h")
plot(table(round(dat_rmnas$number_salmon * dat_rmnas$number_salmon)),
     type = "h")
# not great
#    0     1     4     9    16    25    36    49    64    81   100   144
#25114  3220  1513   409   148    67    42    10     7     3     2     2

# collinearity
vif(full_model_redds)
vif(full_model_salmon)
# redd descriptions all high (depth_m, pot_depth_m, percent_fines, percent_small, percent_med, percent_large, percent_boulder)

# look at space and time...
summary <- data %>%
  group_by(location, month, water_year) %>%
  summarize(total_num_redd = sum(number_redds, na.rm = TRUE),
            sample = n())

