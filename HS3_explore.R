##########################################################
# Created by: Pascale Goertler (pascale.goertler@water.ca.gov)
# Last updated: 1/21/2025
# Description: This script pulls in data from EDI and evaluates data using diagnostics from Zuur et al. 2010
# Intended to explore Feather River data use in Science Plan hypothesis S3
#########################################################
## HS3
## The density of salmonid redds will increase in habitat enhancement areas compared to proximate, non-enhanced areas

# library
library(EDIutils)
library(lattice)
library(car)
library(tidyverse)
library(readxl)
library(sf)
library(leaflet)


# get data
temp <- read_data_entity_names(packageId = "edi.1802.2")
temp_dat <- read_data_entity(packageId = "edi.1802.2", entityId = temp$entityId[1])
data <- readr::read_csv(file = temp_dat)

# view data
head(data)
str(data)
summary(data)

# to get to redd density we need to have stream lengths and/or project area by site
# made for Januray 2025 discussion, no longer needed
# location <- unique(data$location) #49 sites
# size = NA
# ref = NA
# dat_location <- cbind(location, size, ref) # for meeting in Jan 2026
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
  group_by(location, water_year, latitude, longitude) %>%
  summarise(total_num_redd = sum(number_redds, na.rm = TRUE),
            sample = n())
#don't have lat/lon when zero redds observed, need to make general location for map
gen_loc <- subset(summary, total_num_redd==0)
unique(gen_loc$location) #all of them

site_redds <- data %>%
  group_by(location) %>%
  summarize(total_num_redd = sum(number_redds, na.rm = TRUE),
            sample = n())

# add site size and restoration status data (will be added to edi soon)
site_dat <-  read_excel("Copy of FR_Redd Survey Locations.xlsx")
# check that the two data have the same site names
check <- merge(site_dat, dat_location, by = "location", all=TRUE)
# location "big" is additional to redd data, but all redd sites are included

# make map with restoration status and year
dat_redds <- subset(summary, total_num_redd>=1)
data_loc <- unique(dat_redds[,c(1:4)])
map_dat <- merge(site_dat[,-c(1,3)], data_loc, by = "location", all=TRUE)
map_dat_na <- map_dat[!is.na(map_dat$latitude), ]

# restored/not restored as symbol, redd observed before/after restoration in color
# Convert df to sf
dat_4326 <- st_as_sf(map_dat_na,
                     coords = c('longitude', 'latitude'),
                     crs = 4326,
                     remove = F)

head(dat_4326)
plot(dat_4326["restored"])

dat_4326_res <- subset(dat_4326, latitude > 39.48)

ggplot(dat_4326_bedrock,
       aes(color = water_year, shape = when_restored))+
  geom_sf() +
  #ylim(39.51, 39.518) +
  facet_wrap(~restored)

dat_4326_bedrock <- subset(dat_4326, location == "bedrock") # just look at HRL site
dat_4326_bedrock <- subset(dat_4326_bedrock, longitude < 121.564)

dat_4326_ref <- subset(dat_4326_res, water_year>=2018) # possible reference sites for bedrock
unique(dat_4326_ref$location)

ggplot(dat_4326_ref,aes(color = location, shape = restored))+
  facet_wrap(~ water_year) +
  geom_sf()
