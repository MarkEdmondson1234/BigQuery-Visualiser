## in ui.R
library(shiny)
library(shinydashboard)
library(googleAuthR)
library(DT)
library(dygraphs)
library(d3heatmap)
library(listviewer)
library(ggplot2)

header <- dashboardHeader(title = "BigQuery Visualiser")

textareaInput <- function(inputId, label, value="", placeholder="", rows=2){
  tagList(
    div(strong(label), style="margin-top: 5px;"),
    tags$style(type="text/css", "textarea {width:100%; margin-top: 5px;}"),
    tags$textarea(id = inputId, placeholder = placeholder, rows = rows, value))
}

sidebar <- dashboardSidebar(
  sidebarMenu(
    # menuItem(uiOutput("uploadJSON")), ## not available until httr bug fixed
    menuItem("Start Again", href="/", newtab=F, icon=icon("refresh")),
    menuItem("Say Hello :-", href="#", newtab=F),
    menuSubItem("@HoloMarkeD", href="http://twitter.com/HoloMarkeD", icon = icon("twitter")),
    menuSubItem("LinkedIn", href="http://dk.linkedin.com/in/markpeteredmondson", icon = icon("linkedin")),
    menuSubItem("Blog", href="http://markedmondson.me/?utm_source=shinyapps&utm_medium=referral&utm_content=sidebar&utm_campaign=bigQueryVizOpenSource", icon=icon("hand-o-right")),
    menuItem("Other Apps :-", href="#", newtab=F),
    menuSubItem("GA Effect", href="https://gallery.shinyapps.io/ga-effect/", icon = icon("line-chart")),
    menuSubItem("GA Rollup", href="https://mark.shinyapps.io/ga-rollup/", icon = icon("area-chart")),
    menuSubItem("GA Meta", href="https://mark.shinyapps.io/ga-meta/", icon = icon("sitemap"))
    
  )
)

body <- dashboardBody(
      fluidRow(
        tabBox(width = 12,
          tabPanel(tagList(shiny::icon("picture-o"), "Viz"),
            fluidRow(
              box(title="BigQuery SQL", status = "info", width=12, solidHeader = T,
                  textareaInput("bq_sql", "Enter BigQuery SQL Here", "SELECT CAST(year as string) as Year, AVG(weight_pounds) as Average_Weight, AVG(mother_age) as Average_Mother_Age, AVG(father_age) as Average_Father_Age
                                FROM [publicdata:samples.natality] 
                                GROUP BY Year ORDER BY Year", rows=4),
                  helpText("See Query Reference: https://cloud.google.com/bigquery/query-reference"),
                  uiOutput("fetch_data_button")
              )
            ),
            fluidRow(
              tabBox(width = 12,
                     tabPanel("General Plots",
                              fluidRow(
                                box(title = "Plot Output", 
                                    status = "success", width = 12, solidHeader = T,
                                    selectInput("plot_type", "Plot Type",
                                                choices = c("Scatter" = "scatter",
                                                            "Line" =  "line",
                                                            # "Density" = "density",
                                                            "Area" = "area",
                                                            "Bar" = "bar",
                                                            "Dotplot" = "dotplot"
                                                            # "Hex Plot" = "hexplot",
                                                            # "Violin" = "violin"
                                                            )),
                                    fluidRow(
                                      column(3,
                                             selectInput("x_scat", "x-axis", choices=NULL)),
                                      column(3,
                                             selectInput("y_scat", "y-axis", choices=NULL)),
                                      column(3,
                                             selectInput("colour_scat", "Colour", choices=NULL)),
                                      column(3,
                                             selectInput("size_scat", "Size", choices=NULL))
                                    ),
                                    plotOutput("ggplot_p", height = "600px"),
                                    br()
                                )
                              )   
                     ),
                     ## this needs its own tab as d3heatmaps doesn't play nicely with others
                     tabPanel("Heatmap", 
                              fluidRow(
                                box(title = "Plot Output", 
                                    status = "success", width = 12, solidHeader = T,
                                    radioButtons("heat_col", "Color Direction", choices=c("column","row", "none"), inline = TRUE),
                                    helpText("Needs first column to contain categories and more than 2 other columns."),
                                    d3heatmapOutput("heatmap", height = 600),
                                    br()  
                                )
                              )  
                     )
              )               
            )
          ),     
          tabPanel(tagList(shiny::icon("database"), "Data"),
            fluidRow(
              box(title = "SQL Data", status = "info", width = 12, solidHeader = T,
                  helpText("Maximum set at 100,000 rows"),
                  DT::dataTableOutput("sql_data")),
              br()
            )
          ),
          tabPanel(tagList(shiny::icon("info-circle"), "Meta"), 
              conditionalPanel("output.logged_in != 'Waiting'",
                fluidRow(
                  box(title="BigQuery Project", status="success", width = 6, solidHeader = T,
                      selectInput("project_select", label = "Project",
                                  choices = NULL ),
                      helpText("The default BigQuery project to use.")),
                  box(title="BigQuery Datasets", status="success", width = 6, solidHeader = T,
                      selectInput("dataset_select", label="Datasets",
                                  choices = NULL),
                      helpText("The default BigQuery dataset to use."))
                ),
                fluidRow(
                  box(title="BigQuery Tables", status="success", width=12, solidHeader = T,
                      DT::dataTableOutput("bq_tables"),
                      helpText("The tables within the selected dataset. Select a table row to see its schema")
                  )
                  
                ),
                fluidRow(
                  box(title = "Table Metadata", status = "success", width = 12, solidHeader = T,
                      jsoneditOutput("table_meta"))
                ),
                br()                
              )  ## conditionalPanel
          ), ## tabPanel
          br()
        ) 
      ),
  br(),
  helpText("All BigQuery data is deleted once you log out or close the browser.  If you don't log out the access token will expire in ~60 mins."),
helpText("Made in", a("Shiny", href="http://shiny.rstudio.com/"), " using ", a("googleAuthR", href="https://github.com/MarkEdmondson1234/googleAuthR"), " to create ", a("bigQueryR", href="https://github.com/MarkEdmondson1234/bigQueryR")),
  helpText("Released under MIT.  Copyright Sunholo Ltd 2015."),
  textOutput("logged_in")
)

dashboardPage(header, sidebar, body, skin = "black")