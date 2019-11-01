# setup -------------------------------------------------------------------

library(pool);library(tidyverse)

source("pw.R")
source("0.functions.R")

# 0. _fk ------------------------------------------------------------------

fk <- dbGetQuery(KELuser, "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE '%fk'")

fk.list <- list()

for (i in fk$tablename) {
  
  fk.list[i] <- tbl(KELuser, paste(i)) %>% collect()
  
}

# STRUCTURAL DATA ---------------------------------------------------------

setwd("C:/Users/Ondrej_Vostarek/Desktop/MVP/DB/data/2018/raw")

# 1. reading --------------------------------------------------------------

file <- list.files(pattern = '.xlsx')

data.raw <- list()

for (i in file) {
  
     data.new <- read_structural_data(i)
  
     data.raw$plot <- bind_rows(data.raw$plot, data.new$plot)
     data.raw$tree <- bind_rows(data.raw$tree, data.new$tree)
     data.raw$mortality <- bind_rows(data.raw$mortality, data.new$mortality)
     data.raw$microsites <- bind_rows(data.raw$microsites, data.new$microsites)
     data.raw$deadwood <- bind_rows(data.raw$deadwood, data.new$deadwood)
     data.raw$regeneration <- bind_rows(data.raw$regeneration, data.new$regeneration)
     data.raw$regeneration_subplot <- bind_rows(data.raw$regeneration_subplot, data.new$regeneration_subplot)

}

date.id <- unique(data.raw$plot$date)

plot.id <- unique(data.raw$plot$plotid)

tree.db <- tbl(KELuser, "tree") %>% 
  inner_join(., 
             tbl(KELuser, "plot") %>% 
               filter(plotid %in% plot.id & !date %in% date.id) %>%
               group_by(plotid) %>%
               arrange(desc(date)) %>%
               filter(row_number() == 1), 
             by = c("plot_id" = "id")) %>% 
  collect()

# 2. cleaning -------------------------------------------------------------

## check data

### 'plottype' in PLOT needs to be checked/edited manually

error.list <- check_structural_data(data = data.raw, fk = fk.list)

## correct data

data.clean <- clean_structural_data(data = data.raw)

### Check the effect of distinct() on DEADWOOD, REGENERATION and REGENERATION_SUBPLOT!  

# 3. exporting ------------------------------------------------------------

for (i in names(data.clean)) {

  name <- paste(date.id, i, sep = "_")
  
  write.table(data.clean[i], paste0(name, ".csv"), sep = ",", row.names = F, na = "")
    
}

# DENDROCHRONOLOGICAL DATA ------------------------------------------------

setwd("C:/Users/Ondrej_Vostarek/Downloads")

# 1. reading --------------------------------------------------------------

st <- unique(gsub("^(.*)[:.:](.*)[:.:](.*)$", "\\2", list.files(pattern = '.csv')))

data.raw <- list()

for (i in st) {
  
  data.new <- read_dendro_data(i)
  
  data.raw$core <- bind_rows(data.raw$core, data.new$core)
  data.raw$ring <- bind_rows(data.raw$ring, data.new$ring)
  
}

tree.db <- tbl(KELuser, "tree") %>% 
  inner_join(.,
             tbl(KELuser, "plot") %>% 
               filter(standshort %in% st) %>% 
               select(date, plot_id = id),
             by = "plot_id") %>%
  collect()

# 2. cleaning -------------------------------------------------------------

## check data

error.list <- check_dendro_data(data = data.raw, fk = fk.list)

## correct data

data.clean <- list()

data.clean$core <- data.raw$core %>% distinct(., .keep_all = T)
data.clean$ring <- data.raw$ring %>% distinct(., .keep_all = T)

# 3. exporting ------------------------------------------------------------

name <- paste(unique(data.clean$core$date), substr(first(data.clean$core$treeid), 1, 3), st, sep = "_")

write.table(data.clean$core, paste(name, "core.csv", sep = "_"), sep = ",", row.names = F, na = "")
write.table(data.clean$ring, paste(name, "ring.csv", sep = "_"), sep = ",", row.names = F, na = "")

# 4. change species -------------------------------------------------------

change.df <- read.table("change_species.csv", sep = ",", header = T, stringsAsFactors = F) %>% 
  select(treeid, species) %>% 
  inner_join(., 
             tree.db %>% select(id, treeid), 
             by = "treeid")

change.df %>% dbWriteTable(KELadmin, c('public','change'), value = ., row.names = FALSE, overwrite = TRUE)

# disconnection -----------------------------------------------------------

poolClose(KELadmin)
poolClose(KELuser)